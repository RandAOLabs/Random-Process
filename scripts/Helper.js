import { readFileSync } from "node:fs";
import { message, result, createDataItemSigner, spawn } from "@permaweb/aoconnect";

// Load the wallet file
const wallet = JSON.parse(readFileSync("./wallet.json").toString(),);
const availableRandomValues = 44
const providerId = "ld4ncW8yLSkckjia3cw6qO7silUdEe1nsdiEvMoLg-0"
const processId = "nUH3LnpaVCL9jT7J2dT3DfB4V3nkucyNpE3KI9IPxyw"
const tokenId = "OeX1V1xSabUzUtNykWgu9GEaXqacBZawtK12_q5gXaA"
let providers = {
    provider_ids: ["ld4ncW8yLSkckjia3cw6qO7silUdEe1nsdiEvMoLg-0"]
}
const requestIds = [
    "09d4fe31-04f7-415a-8b77-2092cbe70e5d",
    "fedfabf7-49d5-4915-86e5-e547a8fe6e12"
]

const requestId = "00a38f54-a48d-4505-9150-c52a3753658f"
const callbackId = "call me back :("
const input     = "gobledygook"
const modulus   = "7777"
const output    = "shamuckers"
const proof     = "proofs???"

async function updateBalance() {
    let tags = [
        { name: "Action", value: "Update-Providers-Random-Balance" },
    ]

    let id = await message({
        /*
          The arweave TXID of the process, this will become the "target".
          This is the process the message is ultimately sent to.
        */
        process: processId,
        // Tags that the process will use as input.
        tags,
        // A signer function used to build the message "signature"
        signer: createDataItemSigner(wallet),
        /*
          The "data" portion of the message
          If not specified a random string will be generated
        */
        data: JSON.stringify({ availableRandomValues }),
    })

    console.log(id)
    const { Output, Messages } = await result({
        message: id,
        process: processId,
    });
    
    if (Messages && Messages.length > 0) {
        const data = JSON.parse(Messages[0].Data);
        console.log("Status: ", data);
    }
    
    return id;
}

async function getStatus() {
    let tags = [
        { name: "Action", value: "Get-Providers-Random-Balance" },
    ]

    let id = await message({
        /*
          The arweave TXID of the process, this will become the "target".
          This is the process the message is ultimately sent to.
        */
        process: processId,
        // Tags that the process will use as input.
        tags,
        // A signer function used to build the message "signature"
        signer: createDataItemSigner(wallet),
        /*
          The "data" portion of the message
          If not specified a random string will be generated
        */
        data: JSON.stringify({ providerId }),

    })

    //console.log(id)
    const { Output, Messages } = await result({
        message: id,
        process: processId,
    });
    
    if (Messages && Messages.length > 0) {
        const data = JSON.parse(Messages[0].Data);
        console.log("Status: ", data);
    }
    
    return id;
}

async function createRequest() {
    let tags = [
        { name: "Action", value: "Transfer" },
        { name: "Quantity", value: "100" },
        { name: "Recipient", value: processId },
        { name: "X-Providers", value: JSON.stringify(providers) },
        { name: "X-CallbackId", value: callbackId }
    ]

    let id = await message({
        /*
          The arweave TXID of the process, this will become the "target".
          This is the process the message is ultimately sent to.
        */
        process: tokenId,
        // Tags that the process will use as input.
        tags,
        // A signer function used to build the message "signature"
        signer: createDataItemSigner(wallet),
        /*
          The "data" portion of the message
          If not specified a random string will be generated
        */
    })

    console.log(id)
    return id;
}

async function getActiveRequests() {
    let tags = [
        { name: "Action", value: "Get-Open-Random-Requests" },
    ]

    let id = await message({
        /*
          The arweave TXID of the process, this will become the "target".
          This is the process the message is ultimately sent to.
        */
        process: processId,
        // Tags that the process will use as input.
        tags,
        // A signer function used to build the message "signature"
        signer: createDataItemSigner(wallet),
        /*
          The "data" portion of the message
          If not specified a random string will be generated
        */
        data: JSON.stringify({ providerId }),

    })

    //console.log(id)
    const { Output, Messages } = await result({
        message: id,
        process: processId,
    });
    
    if (Messages && Messages.length > 0) {
        const data = JSON.parse(Messages[0].Data);
        console.log("Random Requests: ", data);
    }
    
    return id;
}

async function getRequests() {
    let tags = [
        { name: "Action", value: "Get-Random-Requests" },
    ]

    let id = await message({
        /*
          The arweave TXID of the process, this will become the "target".
          This is the process the message is ultimately sent to.
        */
        process: processId,
        // Tags that the process will use as input.
        tags,
        // A signer function used to build the message "signature"
        signer: createDataItemSigner(wallet),
        /*
          The "data" portion of the message
          If not specified a random string will be generated
        */
        data: JSON.stringify({ requestIds }),

    })

    //console.log(id)
    const { Output, Messages } = await result({
        message: id,
        process: processId,
    });
    
    if (Messages && Messages.length > 0) {
        const data = JSON.parse(Messages[0].Data);
        console.log("Random Requests: ", JSON.stringify(data));
    }
    
    return id;
}

async function getRequestViaCallbackId() {
    let tags = [
        { name: "Action", value: "Get-Random-Request-Via-Callback-Id" },
    ]

    let id = await message({
        /*
          The arweave TXID of the process, this will become the "target".
          This is the process the message is ultimately sent to.
        */
        process: processId,
        // Tags that the process will use as input.
        tags,
        // A signer function used to build the message "signature"
        signer: createDataItemSigner(wallet),
        /*
          The "data" portion of the message
          If not specified a random string will be generated
        */
        data: JSON.stringify({ callbackId }),

    })

    //console.log(id)
    const { Output, Messages } = await result({
        message: id,
        process: processId,
    });
    
    if (Messages && Messages.length > 0) {
        const data = JSON.parse(Messages[0].Data);
        console.log("Random Request: ", JSON.stringify(data));
    }
    
    return id;
}

async function postVDFChallenge() {
    let tags = [
        { name: "Action", value: "Post-VDF-Challenge" },
    ]

    let id = await message({
        /*
          The arweave TXID of the process, this will become the "target".
          This is the process the message is ultimately sent to.
        */
        process: processId,
        // Tags that the process will use as input.
        tags,
        // A signer function used to build the message "signature"
        signer: createDataItemSigner(wallet),
        /*
          The "data" portion of the message
          If not specified a random string will be generated
        */
          data: JSON.stringify({ requestId, input, modulus }),
        })

    //console.log(id)
    const { Output, Messages } = await result({
        message: id,
        process: processId,
    });
    
    if (Messages && Messages.length > 0) {
        const data = JSON.parse(Messages[0].Data);
        console.log("Status: ", data);
    }
    
    return id;
}

async function postVDFOutputAndProof() {
    let tags = [
        { name: "Action", value: "Post-VDF-Output-And-Proof" },
    ]

    let id = await message({
        /*
          The arweave TXID of the process, this will become the "target".
          This is the process the message is ultimately sent to.
        */
        process: processId,
        // Tags that the process will use as input.
        tags,
        // A signer function used to build the message "signature"
        signer: createDataItemSigner(wallet),
        /*
          The "data" portion of the message
          If not specified a random string will be generated
        */
          data: JSON.stringify({ requestId, output, proof }),
        })

    //console.log(id)
    const { Output, Messages } = await result({
        message: id,
        process: processId,
    });
    
    if (Messages && Messages.length > 0) {
        const data = JSON.parse(Messages[0].Data);
        console.log("Status: ", data);
    }
    
    return id;
}

// Main function to call post data
async function main() {
    const inputArg =  process.argv[2];
    
    if (inputArg == 1) {
        try {
            await updateBalance()
        } catch (err) {
            console.error("Error reading process IDs or sending messages:", err);
        }
    } else if (inputArg == 2) {
        try {
            await getStatus()
        } catch (err) {
            console.error("Error reading process IDs or sending messages:", err);
        }
    } else if (inputArg == 3) {
        try {
            await createRequest()
        } catch (err) {
            console.error("Error reading process IDs or sending messages:", err);
        }
    } else if (inputArg == 4) {
        try {
            await getActiveRequests()
        } catch (err) {
            console.error("Error reading process IDs or sending messages:", err);
        }
    } else if (inputArg == 5) {
        try {
            await getRequests()
        } catch (err) {
            console.error("Error reading process IDs or sending messages:", err);
        }
    } else if (inputArg == 6) {
        try {
            await getRequestViaCallbackId()
        } catch (err) {
            console.error("Error reading process IDs or sending messages:", err);
        }
    } else if (inputArg == 7) {
        try {
            await postVDFChallenge()
        } catch (err) {
            console.error("Error reading process IDs or sending messages:", err);
        }
    } else if (inputArg == 8) {
        try {
            await postVDFOutputAndProof()
        } catch (err) {
            console.error("Error reading process IDs or sending messages:", err);
        }
    }
}

main();