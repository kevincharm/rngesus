// import { upgrade__V1_0_0__to__V1_1_0 } from './upgrade__V1_0_0__to__V1_1_0'
// import { upgrade__V1_1_0__to__V1_2_0 } from './upgrade__V1_1_0__to__V1_2_0'
import { upgrade__V1_2_0__to__V1_2_1 } from './upgrade__V1_2_0__to__V1_2_1'

async function main() {
    // await upgrade__V1_0_0__to__V1_1_0()
    // await upgrade__V1_1_0__to__V1_2_0()
    await upgrade__V1_2_0__to__V1_2_1()
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
    console.error(error)
    process.exitCode = 1
})
