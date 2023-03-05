// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import {IRNGesus} from "../interfaces/IRNGesus.sol";
import {IRandomnessReceiver} from "../interfaces/IRandomnessReceiver.sol";

contract Consumer is IRandomnessReceiver {
    address public immutable rngesus;

    uint256 public requestId;

    uint256 public randomness;

    constructor(address rngesus_) {
        rngesus = rngesus_;
    }

    function begin(uint256 deadline) external {
        requestId = IRNGesus(rngesus).requestRandomness(deadline);
    }

    function receiveRandomness(uint256 rid, uint256 rand) external {
        require(requestId == rid, "Request ID didn't match");
        randomness = rand;
    }
}
