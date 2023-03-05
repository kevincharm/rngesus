// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import {BLSSNARKVerifier} from "./BLSSNARKVerifier.sol";
import {BufferSlice} from "./utils/BufferSlice.sol";
import {BigNumbers, BigNumber} from "../vendor/solidity-BigNumber/src/BigNumbers.sol";
import {IRNGesus} from "./interfaces/IRNGesus.sol";
import {IRandomnessReceiver} from "./interfaces/IRandomnessReceiver.sol";

/// @title RNGesus: A drand oracle
/// @author kevincharm
contract RNGesus is IRNGesus {
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
    mapping(uint64 => uint256) public randomness;

    /// @notice What rounds are currently pending
    uint64[] public pendingRounds;
    /// @notice round => requestId;
    mapping(uint64 => uint256[]) private requestIdsInRound;
    /// @notice Request ID => callback contract
    mapping(uint256 => address) private requests;
    event RandomnessRequestReceived();

    /// @notice BLS12-381 field size
    bytes public constant P =
        hex"1a0111ea397fe69a4b1ba7b6434bacd764774b84f38512bf6730d2a0f6b0f6241eabfffeb153ffffb9feffffffffaaab";

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

    /// @notice Convert integer to octet stream
    /// @param value Integer to convert
    /// @param length Byte-length of integer
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

    /// @notice (base ** exp) % modulus using precompile
    function modexp(
        bytes memory base,
        bytes memory exp,
        bytes memory modulus
    ) internal view returns (bool success, bytes memory output) {
        bytes memory input = abi.encodePacked(
            uint256(base.length),
            uint256(exp.length),
            uint256(modulus.length),
            base,
            exp,
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

    /// @notice base % P where P is BLS12-381 field size
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

    /// @notice Produce uniformly random byte string from `message` using SHA256
    /// @param message Message to expand
    /// @param DST Domain separation tag
    /// @param lenInBytes Length of desired byte string
    function expandMessageXMD(
        bytes memory message,
        bytes memory DST,
        uint256 lenInBytes
    ) internal pure returns (bytes memory) {
        uint256 b_in_bytes = 32;
        uint256 r_in_bytes = b_in_bytes * 2;
        uint256 ell = ceilDiv(lenInBytes, b_in_bytes);
        require(ell <= 255, "Invalid xmd length");
        bytes memory DST_prime = abi.encodePacked(DST, i2osp(DST.length, 1)); // CORRECT
        // ---------------------------------------
        bytes memory Z_pad = i2osp(0, r_in_bytes);
        bytes memory l_i_b_str = i2osp(lenInBytes, 2);
        bytes32[] memory b = new bytes32[](ell + 1);
        bytes32 b_0 = sha256(
            abi.encodePacked(Z_pad, message, l_i_b_str, i2osp(0, 1), DST_prime)
        );
        b[0] = sha256(abi.encodePacked(b_0, i2osp(1, 1), DST_prime));
        for (uint256 i = 1; i <= ell; ++i) {
            b[i] = sha256(
                abi.encodePacked(b_0 ^ b[i - 1], i2osp(i + 1, 1), DST_prime)
            );
        }
        // ---------------------------------------
        bytes memory pseudo_random_bytes = abi.encodePacked(b[0]);
        for (
            uint256 i = 1;
            i < lenInBytes / 32 /** each b[i] is bytes32 */;
            ++i
        ) {
            pseudo_random_bytes = abi.encodePacked(pseudo_random_bytes, b[i]);
        }
        return pseudo_random_bytes;
    }

    /// @notice SHA-256 an arbitrary `message` to BLS field
    /// @param message Message to hash
    /// @param count Number of Fp2[Re,Im] elements to produce
    function hashToField(
        bytes memory message,
        uint256 count
    ) internal view returns (bytes[][] memory) {
        uint256 L = 64;
        bytes memory pseudo_random_bytes = expandMessageXMD(
            message,
            "BLS_SIG_BLS12381G2_XMD:SHA-256_SSWU_RO_NUL_",
            count * 2 * L
        );
        bytes[][] memory u = new bytes[][](count);
        bytes[] memory e;
        for (uint256 i; i < count; ++i) {
            e = new bytes[](2);
            for (uint256 j; j < 2; ++j) {
                uint256 elm_offset = L * (j + i * 2);
                bytes memory tv = new bytes(L);
                for (uint256 t; t < L; ++t) {
                    tv[t] = pseudo_random_bytes[elm_offset + t];
                }
                (bool success, bytes memory out) = modP(
                    tv /** TODO: Proper endianness? */
                );
                require(success, "modP failed");
                e[j] = out;
            }
            u[i] = e;
        }
        return u;
    }

    /// @notice 55x7 to big-endian
    /// A = 2^0 * a[0]
    ///     + 2^n * a[1]
    ///     + ...
    ///     + 2^{n(k-1)} * a[k-1]
    function arrayToBigInt(
        uint256[7] memory arr
    ) internal view returns (bytes memory) {
        BigNumber memory sum = BigNumbers.zero();
        for (uint256 i = 0; i < 7; ++i) {
            (bool success, bytes memory exp) = modexp(
                hex"02",
                abi.encodePacked(uint16(55 * i)) /** dec55 */,
                P
            );
            require(success, "modexp55 failed");
            BigNumber memory v = BigNumbers.init(arr[i], false).mul(
                BigNumbers.init(exp, false)
            );
            sum = sum.add(v);
        }
        return sum.val;
    }

    /// @notice Verify random beacon SNARK proof
    /// @param round Random beacon round, will be verified against proof
    /// @param signature Signature of round in 55x7 representation
    /// @param Hm sha256(round), hashed to the BLS field, in 55x7 representation
    /// @param proof SNARK proof, proving BLS verification of signature and Hm
    ///     against known public key
    function verifyBeaconProof(
        uint64 round,
        uint256[7][2][2] calldata signature,
        uint256[7][2][2] calldata Hm,
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
                ++offset;
            }
        }

        // 2. Load signature into proof input [14,42)
        for (uint256 i; i < 2; ++i) {
            for (uint256 j; j < 2; ++j) {
                for (uint256 k; k < 7; ++k) {
                    // TODO: Check if this corresponds to public.json flattening
                    input[offset] = signature[i][j][k];
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
                    ++offset;
                }
            }
        }

        // 4. Verify H(m) == H_c(m) [computed from `round`]
        // TODO: The SNARK proof can include a `hash_to_field` verification circuit
        // Last part is H(m), which is the message, hashed to the field P where
        // message := sha256(bytes(uint64(round)))
        bytes memory message = abi.encodePacked(
            sha256(abi.encodePacked(uint64(round)))
        );
        bytes[][] memory computedHm = hashToField(message, 2);
        // -----------------------------------------------------
        // computedHm is in [[f_0, f_1], [f_0, f_1]] format
        // each f is 48B
        // SNARK inputs are in 55x7 format
        // -> Convert SNARK inputs from 55x7 to [Fp2, Fp2]
        for (uint256 i; i < 2; ++i) {
            for (uint256 j; j < 2; ++j) {
                uint256[7] memory arr;
                for (uint256 k; k < 7; ++k) {
                    arr[k] = Hm[i][j][k];
                }
                bytes memory fp = arrayToBigInt(arr);
                uint256 off = fp.length - 48;
                bytes memory f48 = new bytes(48);
                // TODO: Optimise
                for (uint256 x; x < 48; ++x) {
                    f48[x] = fp[off + x];
                }
                require(
                    keccak256(computedHm[i][j]) == keccak256(f48),
                    "Invalid signed H(m)"
                );
            }
        }
        return
            BLSSNARKVerifier(blsSNARKVerifier).verifyProof(
                proof.a,
                proof.b,
                proof.c,
                input
            );
    }

    /// @notice Record new random beacon given the SNARK proof is valid
    /// @param round Random beacon round, will be verified against proof
    /// @param signature Signature of round in 55x7 representation
    /// @param Hm sha256(round), hashed to the BLS field, in 55x7 representation
    /// @param proof SNARK proof, proving BLS verification of signature and Hm
    ///     against known public key
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

    /// @notice Request a random beacon after a specified timestamp
    /// @param deadline Timestamp after which a random beacon will be proven
    /// @return request ID
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

    /// @notice (Keeper function) check if there are pending rounds to fulfill
    function checkUpkeep() external view returns (bool) {
        return pendingRounds.length != 0;
    }

    /// @notice (Keeper function) fulfill requests once rounds are proven
    function fulfillRequests(uint256 roundIndex, uint256 amount) external {
        uint64 round = pendingRounds[roundIndex];
        uint256 rand = randomness[round];
        require(rand == 0, "Round doesn't exist");

        uint256 length = requestIdsInRound[round].length;
        require(length == 0, "No requests to fulfill");

        uint256 limit = amount < length ? amount : length;
        for (uint256 i; i < limit; ++i) {
            uint256 rLen = requestIdsInRound[round].length;
            uint256 reqId = requestIdsInRound[round][i];
            // Remove request ID from round
            requestIdsInRound[round][i] = requestIdsInRound[round][rLen - 1];
            requestIdsInRound[round].pop();
            // Fulfill request
            address requester = requests[reqId];
            // TODO: try/catch (??)
            IRandomnessReceiver(requester).receiveRandomness(reqId, rand);
        }
        if (requestIdsInRound[round].length == 0) {
            // No more requests for round - all fulfilled
            pendingRounds[roundIndex] = pendingRounds[roundIndex - 1];
            pendingRounds.pop();
        }
    }
}
