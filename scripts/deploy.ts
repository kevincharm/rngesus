import { ethers } from 'hardhat'
import { BLSSNARKVerifier__factory, RNGesus__factory } from '../typechain-types'
import inputs from '../test/public.json'
import proof from '../test/proof.json'
import encodeGroth16ProofArgs from '../test/encodeGroth16Proof'
import { IGroth16Proof } from 'snarkjs'
import { parseEther, parseUnits } from 'ethers/lib/utils'

// Drand unchained testnet 7672797f548f3f4748ac4bf3352fc6c6b6468c9ad40ad456a397545c6e2df5bf
// https://testnet0-api.drand.cloudflare.com/7672797f548f3f4748ac4bf3352fc6c6b6468c9ad40ad456a397545c6e2df5bf/info
const period = 3
const genesisTime = 1651677099
const pubKey55x7: [string[], string[]] = [
    [
        '28113499409755153',
        '9821332782502793',
        '15356694772791369',
        '5221032786067611',
        '6768993040652284',
        '11572850342085671',
        '141008224877248',
    ],
    [
        '33461492476086130',
        '35811493041037339',
        '24227159288510945',
        '26544002735666944',
        '5294409699107852',
        '22752247623743245',
        '194806786582404',
    ],
]

const round = 8762363

async function main() {
    const [deployer] = await ethers.getSigners()
    // const tx = await deployer
    //     .sendTransaction({
    //         to: deployer.address,
    //         value: parseEther('0.001'),
    //     })
    //     .then((tx) => tx.wait(1))
    // console.log(`Test tx: ${tx.transactionHash}`)

    const verifier = await new BLSSNARKVerifier__factory(deployer).deploy({
        gasLimit: 10_000_000,
    })
    await verifier.deployed()
    console.log(`Deployed BLSSNARKVerifier to ${verifier.address}`)
    // const verifier = await new BLSSNARKVerifier__factory(deployer).attach(
    //     '0x9309bd93a8b662d315Ce0D43bb95984694F120Cb'
    // )

    const rngesus = await new RNGesus__factory(deployer).deploy(
        verifier.address,
        pubKey55x7,
        genesisTime,
        period,
        {
            gasLimit: 10_000_000,
        }
    )
    await rngesus.deployed()
    console.log(`Deployed RNGesus to ${rngesus.address}`)
    // const rngesus = await new RNGesus__factory(deployer).attach(
    //     '0xb3a2EAB23AdC21eA78e1851Dd4b1316cb2275D9E'
    // )

    // Post a test proof
    const sig55x7: [[string[], string[]], [string[], string[]]] = [
        [inputs.slice(14, 21), inputs.slice(21, 28)],
        [inputs.slice(28, 35), inputs.slice(35, 42)],
    ]
    const Hm55x7: [[string[], string[]], [string[], string[]]] = [
        [inputs.slice(42, 49), inputs.slice(49, 56)],
        [inputs.slice(56, 63), inputs.slice(63, 70)],
    ]
    const [a, b, c] = encodeGroth16ProofArgs(proof as IGroth16Proof, inputs)
    await rngesus.recordBeaconProof(
        round,
        sig55x7,
        Hm55x7,
        {
            a,
            b,
            c,
        },
        {
            gasLimit: 2_000_000,
        }
    )
}

main().then(() => {
    console.log('Done')
    process.exit(0)
})
// .catch((err) => {
//     console.error(err.stack)
//     process.exit(1)
// })
