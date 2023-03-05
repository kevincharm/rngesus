import { ethers, run } from 'hardhat'
import { TroopFactory__factory, Troop__factory } from '../typechain-types'
import { expectTypeAndVersion } from './lib/expectTypeAndVersion'
import { recordDeployments } from './lib/recordDeployments'

const EXPECTED_OLD_TYPE_AND_VERSION = 'Troop 1.1.0'
const EXPECTED_NEW_TYPE_AND_VERSION = 'Troop 1.2.0'
const CURRENT_TROOP_FACTORY_ADDRESS = '0x98cC5553158f928f82ED1e6F7Ba1A6E2E2EDc4C9'

async function verifyAndWait(address: string, constructorArguments: any[]) {
    console.log(`Verifying ${address}...`)
    try {
        await run('verify:verify', {
            address,
            constructorArguments,
        })
    } catch (err) {
        console.error(`Could not verify ${address}:`, err)
    }
    await sleep(1000) // rate limit for API
}

async function main() {
    const signers = await ethers.getSigners()
    const deployer = signers[0]

    const newTroopImpl = await new Troop__factory(deployer).deploy()
    await newTroopImpl.deployed()
    await expectTypeAndVersion(newTroopImpl.address, EXPECTED_NEW_TYPE_AND_VERSION)

    console.log(`Deployed Troop to: ${newTroopImpl.address}`)
    await recordDeployments([
        {
            contractName: await newTroopImpl.typeAndVersion(),
            address: newTroopImpl.address,
        },
    ])

    console.log('Waiting 2mins for Etherscan to catchup before verifying...')
    await sleep(120_000) // wait 2 minutes for etherscan
    // Verify formulae implementation contracts
    await verifyAndWait(newTroopImpl.address, [])

    const factory = TroopFactory__factory.connect(CURRENT_TROOP_FACTORY_ADDRESS, deployer)
    await factory.deployed()
    // Sanity check before upgrading
    await expectTypeAndVersion(await factory.troopImplementation(), EXPECTED_OLD_TYPE_AND_VERSION)
    await factory.setTroopImplementation(newTroopImpl.address).then((tx) => tx.wait(1))
    await expectTypeAndVersion(await factory.troopImplementation(), EXPECTED_NEW_TYPE_AND_VERSION)
}

async function sleep(ms: number) {
    return new Promise((resolve) => setTimeout(resolve, ms))
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
    console.error(error)
    process.exitCode = 1
})
