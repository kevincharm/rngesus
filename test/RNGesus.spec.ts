import { expect } from 'chai'
import { ethers } from 'hardhat'
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers'
import {
    BLSSNARKVerifier,
    BLSSNARKVerifier__factory,
    RNGesus,
    RNGesus__factory,
} from '../typechain-types'
import { BigNumber } from 'ethers'
import inputs from './public.json'
import proof from './proof.json'
import encodeGroth16ProofArgs from './encodeGroth16Proof'
import { IGroth16Proof } from 'snarkjs'

const period = 3
const genesisTime = 1651677099
const round = 8762363
const sigHex =
    '93a7a258bc4f6ada15233b11e9038d64db376420d3ac097f874ded58ed69ac6de45e4c5b3668e68fbdf2697e7ba70dfb172a5d4c3f8ab190779b8e11eb731dbc577710277191c0ea17804231b5eea338dcb55ff6818e258e36f188a766cbe752'
const pubKeyHex =
    '8200fc249deb0148eb918d6e213980c5d01acd7fc251900d9260136da3b54836ce125172399ddc69c4e3e11429b62c11'

const pubKey55x7: [string[], string[]] = [inputs.slice(0, 7), inputs.slice(7, 14)]
const sig55x7: [[string[], string[]], [string[], string[]]] = [
    [inputs.slice(14, 21), inputs.slice(21, 28)],
    [inputs.slice(28, 35), inputs.slice(35, 42)],
]
const Hm55x7: [[string[], string[]], [string[], string[]]] = [
    [inputs.slice(42, 49), inputs.slice(49, 56)],
    [inputs.slice(56, 63), inputs.slice(63, 70)],
]

describe('RNGesus', () => {
    let deployer: SignerWithAddress
    let bob: SignerWithAddress
    let alice: SignerWithAddress
    let rngesus: RNGesus
    let verifier: BLSSNARKVerifier
    beforeEach(async () => {
        ;[deployer, bob, alice] = await ethers.getSigners()
        verifier = await new BLSSNARKVerifier__factory(deployer).deploy()
        rngesus = await new RNGesus__factory(deployer).deploy(
            verifier.address,
            pubKey55x7,
            genesisTime,
            period
        )
    })

    it('should run happy path', async () => {
        const [a, b, c] = encodeGroth16ProofArgs(proof as IGroth16Proof, inputs)
        expect(
            await rngesus.verifyBeaconProof(round, sig55x7, Hm55x7, {
                a,
                b,
                c,
            })
        ).to.eq(true)
    })
})
