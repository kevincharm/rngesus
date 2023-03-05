// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

interface IRNGesus {
    function requestRandomness(
        uint256 deadline
    ) external payable returns (uint256);
}
