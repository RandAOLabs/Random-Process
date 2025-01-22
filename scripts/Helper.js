import { readFileSync } from "node:fs";
import { message, result, createDataItemSigner, spawn } from "@permaweb/aoconnect";

// Load the wallet file
const wallet = JSON.parse(readFileSync("./hera.json").toString(),);
const availableRandomValues = 44
const providerId    = "ld4ncW8yLSkckjia3cw6qO7silUdEe1nsdiEvMoLg-0"
const providerId2   = "c8Iq4yunDnsJWGSz_wYwQU--O9qeODKHiRdUkQkW2p8"
const providerId3   = "Sr3HVH0Nh6iZzbORLpoQFOEvmsuKjXsHswSWH760KAk"
const processId     = "WYtVAlC2kXWPr8gM1tidWrl2e1PTIDjzQJrWlXC1KeY" // "QeVaQXBmIFfLuc29G5bXnylBIJXqON4naIbZrQTk8Iw"
const randomTesting = "m3h7fUeAcR36tn2y13o4LjNum-mgwCCA8eGiH01AdEc"
const tokenId       = "7enZBOhWsyU3A5oCt8HtMNNPHSxXYJVTlOGOetR9IDw"
let providers = {
    provider_ids: ["ld4ncW8yLSkckjia3cw6qO7silUdEe1nsdiEvMoLg-0"]
}


const requestInputs     = 1
const requestId         = "972b012f-d0b0-4cb5-8f68-0ac73f917e93"
const requestIds = [
    requestId
]
const callbackId        = "e894ec35-057b-4db1-a8bc-2bfd75ebbdac"
const input             = "0xf8e3b0de92842f97fb47b393f45187f2"
const modulus           = "0x40e77a538238e49424de6139311eaee7d7f1e31a0e87b2051e1f94bb4b0ad2d"
const output            = "13497708056"
const proof             = JSON.stringify([
    "0x2888fbced9adbafdda5b31e515a8c984f5d6180b7cf27ebe548b6f62f24c787", 
    "0x1866cbe0f97df7b8ab8271a768b7ec4471ccc01629e4f81a84dc928145397b", 
    "0x2425a26f0d0b93fe968dede7b0232e4dd1f8fae13b18c6c41ac71563958e792",
    "0x37f4b4476ea572b0b8b28d5191784c3b2572b2856e2b80e168cd6a4ed5f3bd7",
    "0xd34117ecb3a563340bb145da1698658b66b07fd3eb79410553196812df80c8", 
    "0x2ec6a14bad9162353a87511397c3dd7369404c4347706711bb26e0bfd66364", 
    "0x18d87f510d2df09f8f8efd115b89f0ff94692a9fd5b860ac7d11d5282d37dc", 
    "0x35c7a083deca1df853e5563ce1df3b04ba549e13179aac8e960570dc8ea2602", 
    "0x151e02f39a049a28af5decb2f349832bfde930ed7e0de5f3443be05a8c81a9a", 
    "0x3e0a75b41cec27131f1de1c832971c1083673e8c8865c6907390f89ef77f06e"
])

const gameId = "1"

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
        data: JSON.stringify({ providerId: providerId }),

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
    const callbackId        = "call me back :("
    const inputNumber       = 11
    let tags = [
        { name: "Action", value: "Transfer" },
        { name: "Quantity", value: "100" },
        { name: "Recipient", value: processId },
        { name: "X-Providers", value: JSON.stringify(providers) },
        { name: "X-CallbackId", value: callbackId },
        { name: "X-RequestedInputs", value: JSON.stringify({requested_inputs: inputNumber})}
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
        data: JSON.stringify({ providerId: providerId }),

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

async function requestRandomTester() {
    let tags = [
        { name: "Action", value: "High-or-Low" },
    ]

    let id = await message({
        /*
          The arweave TXID of the process, this will become the "target".
          This is the process the message is ultimately sent to.
        */
        process: randomTesting,
        // Tags that the process will use as input.
        tags,
        // A signer function used to build the message "signature"
        signer: createDataItemSigner(wallet),
        /*
          The "data" portion of the message
          If not specified a random string will be generated
        */
        })

    return id;
}

async function simulateResponse() {
    let tags = [
        { name: "Action", value: "Simulate-Response" },
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

async function sendQuery() {
    let tags = [
        { name: "Action", value: "Check-Status-Via-Callback" },
    ]

    let id = await message({
        /*
          The arweave TXID of the process, this will become the "target".
          This is the process the message is ultimately sent to.
        */
        process: randomTesting,
        // Tags that the process will use as input.
        tags,
        // A signer function used to build the message "signature"
        signer: createDataItemSigner(wallet),
        /*
          The "data" portion of the message
          If not specified a random string will be generated
        */

    })

    return id;
}

async function highLow() {
    let tags = [
        { name: "Action", value: "High-or-Low" },
        { name: "Guess", value: "Higher" }
    ]

    let id = await message({
        /*
          The arweave TXID of the process, this will become the "target".
          This is the process the message is ultimately sent to.
        */
        process: randomTesting,
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

async function viewGame() {
    let tags = [
        { name: "Action", value: "View-Game" },
        { name: "GameId", value: gameId }
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

async function stake() {
    let tags = [
        { name: "Action", value: "Transfer" },
        { name: "Quantity", value: "100000000000000000000" },
        { name: "Recipient", value: processId },
        { name: "X-Stake", value: "true" },
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

async function viewStake() {
    let tags = [
        { name: "Action", value: "View-Provider-Stake" },
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
        data: JSON.stringify({ providerId: providerId }),

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

async function unstake() {
    let tags = [
        { name: "Action", value: "Unstake" },
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
        data: JSON.stringify({ providerId: providerId }),

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
    } else if (inputArg == 9) {
        try {
            await requestRandomTester()
        } catch (err) {
            console.error("Error reading process IDs or sending messages:", err);
        }
    } else if (inputArg == 10) {
        try {
            await simulateResponse()
        } catch (err) {
            console.error("Error reading process IDs or sending messages:", err);
        }
    } else if (inputArg == 11) {
        try {
            await sendQuery()
        } catch (err) {
            console.error("Error reading process IDs or sending messages:", err);
        }
    } else if (inputArg == 12) {
        try {
            await highLow()
        } catch (err) {
            console.error("Error reading process IDs or sending messages:", err);
        }
    } else if (inputArg == 13) {
        try {
            await viewGame()
        } catch (err) {
            console.error("Error reading process IDs or sending messages:", err);
        }
    } else if (inputArg == 14) {
        try {
            await stake()
        } catch (err) {
            console.error("Error reading process IDs or sending messages:", err);
        }
    } else if (inputArg == 15) {
        try {
            await viewStake()
        } catch (err) {
            console.error("Error reading process IDs or sending messages:", err);
        }
    } else if (inputArg == 16) {
        try {
            await unstake()
        } catch (err) {
            console.error("Error reading process IDs or sending messages:", err);
        }
    } 
}

main();