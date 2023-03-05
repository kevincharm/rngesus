# RNGesus

RNGesus is a DRAND oracle. Consuming contracts may request a random beacon from the future. A random beacon can be proved by anyone who can supply a valid SNARK proof of verification of the BLS signature for that round.

This project uses BLS12-381 verification circuits from [0xPARC's circom-pairing](https://github.com/yi-sun/circom-pairing) project to (somewhat) efficiently perform BLS12-381 signature verification on the EVM.

Many optimisations can be made including adding a hash_to_field verification circuit so that this expensive operation does not need to be done in Solidity (would save ~850k gas).

## Requesting a random number

A contract that wants to receive a random number may request a random number from the `RNGesus` contract by calling the `IRNGesus#requestRandomness(uint256 deadline)` function. The deadline must be a future block timestamp. A prover will be able to fulfill this request with a random beacon from the nearest round on or after this deadline.

```solidity
import { IRNGesus } from 'rngesus/contracts/interfaces/IRNGesus.sol';

contract Consumer {
    function begin(uint256 deadline) external {
        requestId = IRNGesus(rngesus).requestRandomness(deadline);
    }
}

```

The calling contract should also implement the `IRandomnessReceiver` interface in order to receive the random beacon after its validity has been proven.

```solidity
import { IRandomnessReceiver } from 'rngesus/contracts/interfaces/IRandomnessReceiver.sol';

contract Consumer is IRandomnessReceiver {
    function receiveRandomness(uint256 rid, uint256 rand) external {
        require(requestId == rid, "Request ID didn't match");
        randomness = rand;
    }
}

```
