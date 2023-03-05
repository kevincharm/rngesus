import * as ethers from 'ethers'

// Calculate keccak256(preimage) - 1
export function calculateStorageSlot(preimage: string) {
    const hash = ethers.utils.solidityKeccak256(['string'], [preimage])
    const slot = ethers.BigNumber.from(hash).sub(1).toHexString()
    console.log('')
    console.log(`// keccak256("${preimage}") - 1`)
    const preImageVarName =
        preimage
            .split('.')
            .at(-1)!
            .replace(/([a-z])([A-Z])/g, '$1_$2')
            .toUpperCase() + '_SLOT'
    console.log(`bytes32 internal constant ${preImageVarName} = ${slot};`)
    console.log('')
}

if (require.main === module) {
    calculateStorageSlot(process.argv[2])
}
