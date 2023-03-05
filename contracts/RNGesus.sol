// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {BLSSNARKVerifier} from "./BLSSNARKVerifier.sol";
import {BufferSlice} from "./utils/BufferSlice.sol";
import {BigNumbers, BigNumber} from "../vendor/solidity-BigNumber/src/BigNumbers.sol";

import "hardhat/console.sol";

/// @title RNGesus: A drand oracle
/// @author kevincharm
contract RNGesus {
    using BigNumbers for BigNumber;
    using BufferSlice for bytes;
    using BufferSlice for BufferSlice.Slice;

    struct SNARKProof {
        uint[2] a;
        uint[2][2] b;
        uint[2] c;
    }
    /// @notice BLS12-381 SNARK verifier contract
    address public immutable blsSNARKVerifier;
    /// @notice drand network's public key in base-22^5
    uint256[7][2] public publicKey;
    /// @notice UNIX timestamp of this drand network's first beacon
    uint256 public immutable genesisTimestamp;
    /// @notice Interval between random beacons
    uint64 public immutable period;

    /// @notice Randomness values that have been previously proven
    mapping(uint64 => uint256) private randomness;

    bytes public constant P =
        hex"1a0111ea397fe69a4b1ba7b6434bacd764774b84f38512bf6730d2a0f6b0f6241eabfffeb153ffffb9feffffffffaaab" /** field size */;

    uint256 public nextRequestId;

    event NewRandomBeacon(
        uint64 round,
        uint256[7][2][2] signature,
        SNARKProof proof
    );

    error InvalidProof(
        uint64 round,
        uint256[7][2][2] signature,
        SNARKProof proof
    );
    error AlreadyProven(uint64 round);

    constructor(
        address verifier_,
        uint256[7][2] memory publicKey_,
        uint256 genesisTimestamp_,
        uint64 period_
    ) {
        blsSNARKVerifier = verifier_;
        for (uint256 i; i < 2; ++i) {
            for (uint256 k; k < 7; ++k) {
                publicKey[i][k] = publicKey_[i][k];
            }
        }

        require(block.timestamp >= genesisTimestamp_, "Wait for genesis");
        genesisTimestamp = genesisTimestamp_;

        require(period_ != 0, "Period must be nonzero");
        period = period_;
    }

    function ceilDiv(uint256 a, uint256 b) internal pure returns (uint256) {
        return (a + b - 1) / b;
    }

    function i2osp(
        uint256 value,
        uint256 length
    ) internal pure returns (bytes memory) {
        bytes memory res = new bytes(length);
        for (int256 i = int256(length) - 1; i >= 0; --i) {
            res[uint256(i)] = bytes1(uint8(value & 0xff));
            value >>= 8;
        }
        return res;
    }

    /// @notice Perform base % mod using the modexp precompile with exp=1
    function modP(
        bytes memory base
    ) internal view returns (bool success, bytes memory output) {
        // base**1 % mod
        bytes memory modulus = P;
        bytes memory input = abi.encodePacked(
            uint256(base.length),
            uint256(1) /** len(exp) == 1B */,
            uint256(modulus.length),
            base,
            hex"01" /** exp == 1 */,
            modulus
        );

        output = new bytes(modulus.length);

        assembly {
            success := staticcall(
                gas(),
                5,
                add(input, 32),
                mload(input),
                add(output, 32),
                mload(modulus)
            )
        }
    }

    function expand_message_xmd(
        bytes memory message,
        bytes memory DST,
        uint256 lenInBytes
    ) internal pure returns (bytes memory) {
        uint256 b_in_bytes = 32;
        uint256 r_in_bytes = b_in_bytes * 2;
        uint256 ell = ceilDiv(lenInBytes, b_in_bytes);
        require(ell <= 255, "Invalid xmd length");
        bytes memory DST_prime = abi.encodePacked(DST, i2osp(DST.length, 1));
        bytes memory Z_pad = i2osp(0, r_in_bytes);
        bytes memory l_i_b_str = i2osp(lenInBytes, 2);
        bytes32[] memory b = new bytes32[](ell);
        bytes32 b_0 = sha256(
            abi.encodePacked(Z_pad, message, l_i_b_str, i2osp(0, 1), DST_prime)
        );
        b[0] = sha256(abi.encodePacked(b_0, i2osp(1, 1), DST_prime));
        for (uint256 i = 1; i <= ell; ++i) {
            b[i] = sha256(
                abi.encodePacked(b_0 ^ b[i - 1], i2osp(i + 1, 1), DST_prime)
            );
        }
        // TODO: Optimise
        bytes memory pseudo_random_bytes;
        for (uint256 i; i < lenInBytes; ++i) {
            pseudo_random_bytes = abi.encodePacked(pseudo_random_bytes, b[i]);
        }
        return pseudo_random_bytes;
    }

    function hashToField(
        bytes memory message,
        uint256 count
    ) internal view returns (bytes[][] memory) {
        // uint256 log2p = 381;
        // uint256 k = 128; // target security level
        // uint256 m = 2; // extension degree of F, m >= 1
        uint256 L = ceilDiv(381 + 128, 8); // section 5.1 of ietf draft link above
        bytes memory pseudo_random_bytes = expand_message_xmd(
            message,
            "BLS_SIG_BLS12381G2_XMD:SHA-256_SSWU_RO_NUL_",
            count * 2 * L
        );
        bytes[][] memory u = new bytes[][](count);
        bytes[] memory e;
        uint256 i;
        uint256 j;
        uint256 t;
        bytes memory tv;
        uint256 elm_offset;
        bool success;
        bytes memory out;
        for (i = 0; i < count; ++i) {
            e = new bytes[](2);
            for (j = 0; j < 2; ++j) {
                elm_offset = L * (j + i * 2);
                tv = new bytes(L);
                for (t = 0; t < L; ++t) {
                    tv[t] = pseudo_random_bytes[elm_offset + t];
                }
                (success, out) = modP(tv /** TODO: Proper endianness? */);
                require(success, "modP failed");
                e[j] = out;
            }
            u[i] = e;
        }
        return u;
    }

    /// @notice Convert arbitrary bigint to 55x7
    function bigint_to_array(
        uint256 x
    ) internal pure returns (uint256[] memory) {
        uint256 mod = 2 ** 55;
        uint256 k = 7;
        uint256[] memory ret = new uint256[](k);
        uint256 x_temp = x;
        for (uint256 i; i < k; ++i) {
            ret[i] = (x_temp % mod);
            x_temp = x_temp / mod;
        }
        return ret;
    }

    /// @notice 55x7 to big-endian
    function array_to_bigint(
        uint256[7] memory arr
    ) internal view returns (bytes memory) {
        BigNumber memory sum = BigNumbers.zero();
        for (uint256 i = 0; i < 7; --i) {
            uint256 v = arr[i] * 2 ** (55 * (i));
            sum = sum.add(BigNumbers.init(v, false));
        }
        return sum.val;
    }

    function verifyBeaconProof(
        uint64 round,
        uint256[7][2][2] calldata signature /** from public.json */,
        uint256[7][2][2] calldata Hm /** hashed to field */,
        SNARKProof calldata proof
    ) public view returns (bool) {
        // The structure of the public inputs to the SNARK proof is as follows.
        // signal input pubkey[2][k];
        // signal input signature[2][2][k];
        // signal input Hm[2][2][k];

        uint256 offset = 0;
        uint256[70] memory input;
        // 1. Force known immutable public keys as the inputs to the proof
        for (uint256 i; i < 2; ++i) {
            for (uint256 k; k < 7; ++k) {
                input[offset] = publicKey[i][k];
                console.log("[%d] %d", offset, input[offset]);
                ++offset;
            }
        }

        // 2. Load signature into proof input [14,42)
        for (uint256 i; i < 2; ++i) {
            for (uint256 j; j < 2; ++j) {
                for (uint256 k; k < 7; ++k) {
                    // TODO: Check if this corresponds to public.json flattening
                    input[offset] = signature[i][j][k];
                    console.log("[%d] %d", offset, input[offset]);
                    ++offset;
                }
            }
        }

        // 3. Load H(m) [[hashed to field]] into proof input [42, 70)
        for (uint256 i; i < 2; ++i) {
            for (uint256 j; j < 2; ++j) {
                for (uint256 k; k < 7; ++k) {
                    // TODO: Check if this corresponds to public.json flattening
                    input[offset] = Hm[i][j][k];
                    console.log("[%d] %d", offset, input[offset]);
                    ++offset;
                }
            }
        }

        // // Last part is H(m), which is the message, hashed to the field P where
        // // message := sha256(bytes(uint64(round)))
        // bytes memory message = abi.encodePacked(
        //     sha256(abi.encodePacked(uint64(round)))
        // );
        // // H(m) := hash_to_field(message)
        // bytes[][] memory Hm = hashToField(message, 2);
        // // H(m) is in [[f_0, f_1], [f_0, f_1]] format
        // // SNARK inputs are in 55x7 format
        // for (uint256 i; i < 2; ++i) {
        //     for (uint256 j; j < 2; ++j) {
        //         uint256[7] memory f;
        //         for (uint256 k; k < 7; ++k) {
        //             f[k] = input[offset + k];
        //             ++offset;
        //         }
        //         bytes memory h = array_to_bigint(f);
        //         require(keccak256(Hm[i][j]) == keccak256(h), "Invalid Hm");
        //     }
        // }
        return
            BLSSNARKVerifier(blsSNARKVerifier).verifyProof(
                proof.a,
                proof.b,
                proof.c,
                input
            );
    }

    /// @param signature flattened 2x2x7 sig
    function recordBeaconProof(
        uint64 round,
        uint256[7][2][2] calldata signature,
        uint256[7][2][2] calldata Hm,
        SNARKProof calldata proof
    ) external {
        if (randomness[round] != 0) {
            revert AlreadyProven(round);
        }
        if (!verifyBeaconProof(round, signature, Hm, proof)) {
            revert InvalidProof(round, signature, proof);
        }
        emit NewRandomBeacon(round, signature, proof);

        // TODO: Convert `signature` back from 55x7 to G2 represented in
        // bytes32, then sha256 that to produce the same canonical
        // randomness that is emitted by the beacon
        randomness[round] = uint256(sha256(abi.encodePacked(signature)));
    }

    /// @notice What rounds are currently pending
    uint64[] private rounds;
    /// @notice round => requestId;
    mapping(uint64 => uint256[]) private requestIdsInRound;
    /// @notice Request ID => callback contract
    mapping(uint256 => address) private requests;
    event RandomnessRequestReceived();

    function requestRandomness(
        uint256 deadline
    ) external payable returns (uint256) {
        uint256 rid = nextRequestId;
        nextRequestId++;

        // Set callback contract
        requests[rid] = msg.sender;

        // Calculate nearest round from deadline (rounding to the future)
        require(
            deadline >= block.timestamp + period,
            "Deadline must be in the future"
        );
        uint256 delta = deadline - genesisTimestamp;
        uint64 round = uint64((delta / period) + (delta % period));
        requestIdsInRound[round].push(rid);

        return rid;
    }

    function checkUpkeep() external view returns (uint64) {
        if (rounds.length == 0) {
            return 0;
        }

        return rounds[0];
    }

    // TODO: Gas limits
    function fulfillRequests(uint64 round, uint256 amount) external {
        uint256 rand = randomness[round];
        require(rand == 0, "Round doesn't exist");

        uint256 length = requestIdsInRound[round].length;
        require(length == 0, "No requests to fulfill");

        uint256 limit = amount < length ? amount : length;
        for (uint256 i; i < limit; ++i) {
            uint256 reqId = requestIdsInRound[round][i];
            address requester = requests[reqId];
            // TODO: try/catch (??)
            IRandomnessReceiver(requester).receiveRandomness(reqId, rand);
        }
    }
}

interface IRandomnessReceiver {
    function receiveRandomness(uint256 requestId, uint256 randomness) external;
}
