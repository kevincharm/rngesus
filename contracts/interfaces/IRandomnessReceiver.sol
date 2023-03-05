// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

interface IRandomnessReceiver {
    function receiveRandomness(uint256 requestId, uint256 randomness) external;
}
