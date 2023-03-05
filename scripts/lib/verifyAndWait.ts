import { run } from 'hardhat'
import { sleep } from './sleep'

export async function verifyAndWait(address: string, constructorArguments: any[]) {
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
