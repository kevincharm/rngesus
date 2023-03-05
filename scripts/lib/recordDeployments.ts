import path from 'path'
import fs from 'fs/promises'

const DEPLOYMENTS_PATH = path.resolve(__dirname, '../../deployments.json')

export async function recordDeployments(infos: { contractName: string; address: string }[]) {
    let deployments: Record<string, string> = {}
    try {
        deployments = JSON.parse(
            await fs.readFile(DEPLOYMENTS_PATH, {
                encoding: 'utf-8',
            })
        )
    } catch (err) {
        console.warn(`No valid deployment JSON found, creating one`)
    }

    for (const { contractName, address } of infos) {
        deployments[contractName] = address
    }

    // Write to file
    await fs.writeFile(DEPLOYMENTS_PATH, JSON.stringify(deployments, null, 2), {
        encoding: 'utf-8',
    })
}
