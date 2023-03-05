import { ethers } from 'hardhat'
import { ITypeAndVersion__factory } from '../../typechain-types'

export async function expectTypeAndVersion(address: string, expectedTypeAndVersion: string) {
    const typeAndVersion = await ITypeAndVersion__factory.connect(
        address,
        ethers.provider
    ).typeAndVersion()
    if (typeAndVersion !== expectedTypeAndVersion) {
        throw new Error(
            `Expected contract to be ${expectedTypeAndVersion} but found ${typeAndVersion}`
        )
    }
    console.log(`✅ Contract typeAndVersion is as expected: ${typeAndVersion}`)
}
