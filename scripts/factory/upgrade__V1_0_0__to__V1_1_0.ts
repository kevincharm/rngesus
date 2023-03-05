import { ethers } from 'hardhat'
import { TroopFactory__factory, UUPSUpgradeable__factory } from '../../typechain-types'
import { recordDeployments } from '../lib/recordDeployments'
import { sleep } from '../lib/sleep'
import { verifyAndWait } from '../lib/verifyAndWait'
import { ENZYME_UTILS_ADDRESS, CURRENT_TROOP_FACTORY_ADDRESS } from './constants'

export async function upgrade__V1_0_0__to__V1_1_0() {
    const signers = await ethers.getSigners()
    const deployer = signers[0]

    const newTroopFactoryImplementation = await new TroopFactory__factory(deployer).deploy(
        ENZYME_UTILS_ADDRESS
    )
    console.log(
        `Deployed new TroopFactory implementation to: ${newTroopFactoryImplementation.address}`
    )
    await recordDeployments([
        {
            contractName: await newTroopFactoryImplementation.typeAndVersion(),
            address: newTroopFactoryImplementation.address,
        },
    ])

    console.log('Waiting 2mins for Etherscan to catchup before verifying...')
    await sleep(120000) // wait 2 minutes for etherscan

    // Verify new implementation
    await verifyAndWait(newTroopFactoryImplementation.address, [ENZYME_UTILS_ADDRESS])

    const troopFactory = UUPSUpgradeable__factory.connect(CURRENT_TROOP_FACTORY_ADDRESS, deployer)
    await troopFactory.deployed()
    await troopFactory.upgradeTo(newTroopFactoryImplementation.address)
    console.log('Done')
}
