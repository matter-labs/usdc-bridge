require('dotenv').config();
const { Provider, Wallet } = require('zksync-ethers');

const l1Provider = new Provider(process.env.SEPOLIA_RPC_URL); // L1 provider
const l2Provider = new Provider(process.env.SOPHON_RPC_URL); // L2 provider
const privateKey = process.env.PRIVATE_KEY;
const senderWallet = new Wallet(privateKey, l2Provider, l1Provider);

async function main() {
    try {
        // extract params from command line
        const args = process.argv.slice(2);
        const isProofOnly = args.includes('--proof');

        const hashIndex = args.indexOf('--hash');
        if (hashIndex === -1 || hashIndex + 1 >= args.length) {
            throw new Error("Missing required parameter: --hash");
        }
        const hash = args[hashIndex + 1];

        const finalizationHandle = await senderWallet.finalizeWithdrawalParams(hash);
        if (isProofOnly) { 
            console.log(JSON.stringify(finalizationHandle.proof));
        } else {
            delete finalizationHandle.proof;
            console.log(JSON.stringify(finalizationHandle));
        }
    } catch (error) {
        const sender = "0x0000000000000000000000000000000000000000";
        console.log(JSON.stringify({l1BatchNumber: 0,
            l2MessageIndex: 0,
            l2TxNumberInBlock: 0,
            message: error.message,
            sender,
        }))
    }
}

main();
