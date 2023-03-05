```diff
-PROOF OF CONCEPT // 3AM YOLO PUSH // UNOPTIMISED // UNAUDITED // DO NOT USE IN PROD // ET CETERA
```

# RNGesus

**_RNGesus is the saviour to all EVM networks that lack infrastructure to provide verifiable randomness. Powered by [drand](https://drand.love)._**

Consuming contracts may request a random beacon from the future. A random beacon can be proved by anyone who can supply a valid SNARK proof of verification of the BLS signature for that round.

This project uses BLS12-381 verification circuits from [0xPARC's circom-pairing](https://github.com/yi-sun/circom-pairing) ([forked here](https://github.com/kevincharm/circom-pairing)) project to (somewhat) efficiently perform BLS12-381 signature verification on the EVM.

Many optimisations can be made including adding a hash_to_field verification circuit so that this expensive operation does not need to be done in Solidity (would save ~850k gas).

## Deployed addresses

### Scroll Alpha

RNGesus: [0xb3a2EAB23AdC21eA78e1851Dd4b1316cb2275D9E](https://blockscout.scroll.io/address/0xb3a2EAB23AdC21eA78e1851Dd4b1316cb2275D9E)

BLSSNARKVerifier: [0x9309bd93a8b662d315Ce0D43bb95984694F120Cb](https://blockscout.scroll.io/address/0x9309bd93a8b662d315Ce0D43bb95984694F120Cb)

Test random beacon proof tx: [0x14776cbe5e2999ffdc2b7ec71c3b708487e4c1ec9af3dbac1e5e462327a6441b](https://blockscout.scroll.io/tx/0x14776cbe5e2999ffdc2b7ec71c3b708487e4c1ec9af3dbac1e5e462327a6441b)

### Base Goerli

RNGesus: [0xa6a10668c93d532643e2e4511c2e668537288643](https://goerli.basescan.org/address/0xa6a10668c93d532643e2e4511c2e668537288643)

BLSSNARKVerifier: [0xb3a2EAB23AdC21eA78e1851Dd4b1316cb2275D9E](https://goerli.basescan.org/address/0xb3a2eab23adc21ea78e1851dd4b1316cb2275d9e)

Test random beacon proof tx: [0x1552867bfb9acb3d2326d01a90a6622cf96ca793e9ff7cfbefd1e0619d65c4cb](https://goerli.basescan.org/tx/0x1552867bfb9acb3d2326d01a90a6622cf96ca793e9ff7cfbefd1e0619d65c4cb)

### Aurora Testnet

RNGesus: [0xA6A10668c93d532643e2e4511c2E668537288643](https://explorer.testnet.aurora.dev/address/0xA6A10668c93d532643e2e4511c2E668537288643)

BLSSNARKVerifier: [0xb3a2EAB23AdC21eA78e1851Dd4b1316cb2275D9E](https://explorer.testnet.aurora.dev/address/0xb3a2EAB23AdC21eA78e1851Dd4b1316cb2275D9E)

## Mantle Testnet

RNGesus: [0xb3a2EAB23AdC21eA78e1851Dd4b1316cb2275D9E](https://explorer.testnet.mantle.xyz/address/0xb3a2EAB23AdC21eA78e1851Dd4b1316cb2275D9E)

BLSSNARKVerifier: [0x9309bd93a8b662d315Ce0D43bb95984694F120Cb](https://explorer.testnet.mantle.xyz/address/0x9309bd93a8b662d315Ce0D43bb95984694F120Cb)

Test random beacon proof tx: [0xd05493353faa39b2d68e669daa8ec18465bd40b832f9bc7a1426e18f6b380c5e](https://explorer.testnet.mantle.xyz/tx/0xd05493353faa39b2d68e669daa8ec18465bd40b832f9bc7a1426e18f6b380c5e)

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

## Development

This project makes use of git submodules, which need to be initialised:

```sh
git submodule init
git submodule update
```

To install dependencies:

```sh
# Make sure yarn is installed
npm install -g yarn
# Install dependencies
yarn
```

Running tests:

```sh
yarn test
```
