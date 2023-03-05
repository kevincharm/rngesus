import { IGroth16Proof } from 'snarkjs'
import bigInt from 'big-integer'

type StringDouble = [string, string]

const toHexString = (n: string) => '0x' + bigInt(n).toString(16)

export default function encodeGroth16ProofArgs<P extends string[]>(proof: IGroth16Proof, pub: P) {
    const a = ([proof.pi_a[0], proof.pi_a[1]] as StringDouble).map(toHexString) as StringDouble
    const b = (
        [
            [proof.pi_b[0][1], proof.pi_b[0][0]],
            [proof.pi_b[1][1], proof.pi_b[1][0]],
        ] as [StringDouble, StringDouble]
    ).map((p) => p.map(toHexString)) as [StringDouble, StringDouble]
    const c = ([proof.pi_c[0], proof.pi_c[1]] as StringDouble).map(toHexString) as StringDouble

    return [a, b, c, pub] as [StringDouble, [StringDouble, StringDouble], StringDouble, P]
}
