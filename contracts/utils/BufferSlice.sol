// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

/// @title BufferSlice
/// @author kevincharm
/// @notice Create views into buffer slices
library BufferSlice {
    /// @notice View into a buffer
    struct Slice {
        uint256 length;
        uint256 ptr;
    }

    /// @notice Get a view into a buffer slice without copying the source buffer
    /// @param self Source buffer
    /// @return slice Mutable buffer slice
    function toSlice(
        bytes memory self
    ) internal pure returns (Slice memory slice) {
        uint256 len;
        uint256 ptr;
        assembly {
            len := mload(self)
            ptr := add(self, 0x20)
        }
        return Slice({length: len, ptr: ptr});
    }

    /// @notice Create a buffer from a slice (creates a copy)
    /// @param self Slice
    /// @return ret Copy of slice as a new buffer
    function toBuffer(
        Slice memory self
    ) internal pure returns (bytes memory ret) {
        // Adapted from {BytesUtils#memcpy} from:
        // @ensdomains/ens-contracts/contracts/dnssec-oracle/BytesUtils.sol
        uint256 len = self.length;
        ret = new bytes(len);
        uint256 src = self.ptr;
        uint256 dest;
        assembly {
            dest := add(ret, 0x20)
            // Copy word-length chunks while possible
            for {
                //
            } lt(32, len) {
                len := sub(len, 32)
            } {
                mstore(dest, mload(src))
                dest := add(dest, 32)
                src := add(src, 32)
            }

            // Copy remaining bytes
            let mask := sub(exp(256, sub(32, len)), 1)
            let srcpart := and(mload(src), not(mask))
            let destpart := and(mload(dest), mask)
            mstore(dest, or(destpart, srcpart))
        }
    }

    /// @notice Get a new slice of a buffer from an existing slice and some offset
    /// @param offset Offset into the slice
    /// @param length Length of slice after the offset
    /// @return new slice
    function getSlice(
        Slice memory self,
        uint256 offset,
        uint256 length
    ) internal pure returns (Slice memory) {
        require(
            self.ptr + self.length >= self.ptr + offset + length,
            "Slice out-of-bounds"
        );
        return Slice({length: length, ptr: self.ptr + offset});
    }
}
