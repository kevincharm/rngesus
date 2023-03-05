import { parseEther } from 'ethers/lib/utils'
import { ethers, run } from 'hardhat'
import { ERC1967Proxy__factory, LensClubChef__factory, LensClub__factory } from '../typechain-types'
import { recordDeployments } from './lib/recordDeployments'
import { verifyAndWait } from './lib/verifyAndWait'

const CREATION_FEE = parseEther('0.1')
const ACTION_FEE = parseEther('0.1')
const LENS_HUB_PROXY_ADDRESS = '0xDb46d1Dc155634FbC732f92E853b10B288AD5a1d' // Polygon Mainnet
const TROOP_TREASURY = '0xCE2dE789aE9e10D894362a5F0232e5176BcE36F1' /** MATIC ONLY */
const ADMINS = ['0x4fFACe9865bDCBc0b36ec881Fa27803046A88736' /** DEV ONLY */, TROOP_TREASURY]

async function main() {
    const signers = await ethers.getSigners()
    const deployer = signers[0]

    // Deploy master copies
    const lensClubFactoryMasterCopy = await new LensClubChef__factory(deployer).deploy()
    const lensClubMasterCopy = await new LensClub__factory(deployer).deploy()
    await Promise.all([lensClubFactoryMasterCopy.deployed(), lensClubMasterCopy.deployed])

    // Deploy factory proxy
    const { data: initFactoryTxData } = await lensClubFactoryMasterCopy.populateTransaction.init(
        LENS_HUB_PROXY_ADDRESS,
        lensClubMasterCopy.address,
        ethers.constants.HashZero,
        TROOP_TREASURY,
        CREATION_FEE,
        ACTION_FEE
    )
    const lensClubChefProxy = await new ERC1967Proxy__factory(deployer).deploy(
        lensClubFactoryMasterCopy.address,
        initFactoryTxData!
    )
    await lensClubChefProxy.deployed()
    const lensClubChef = await new LensClubChef__factory(deployer).attach(lensClubChefProxy.address)
    console.log(`Deployed LensClubChef: ${lensClubChef.address}`)
    await recordDeployments([
        {
            contractName: await lensClubChef.typeAndVersion(),
            address: lensClubChef.address,
        },
    ])

    // Set admins
    for (const admin of ADMINS) {
        await lensClubChef.setAdmin(admin, true)
        console.log(`Added ${admin} as admin to TroopFactory`)
    }

    // console.log('Waiting 2mins for Etherscan to catchup before verifying...')
    // await sleep(120_000) // wait 2 minutes for etherscan
    // // Verify everything
    // await verifyAndWait(lensClubFactoryMasterCopy.address, [])
    // await verifyAndWait(lensClubMasterCopy.address, [])
    // await verifyAndWait(lensClubChefProxy.address, [
    //     lensClubFactoryMasterCopy.address,
    //     initFactoryTxData,
    // ])
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
