import { readFileSync } from "node:fs";
import { message, result, createDataItemSigner, spawn } from "@permaweb/aoconnect";

// Load the wallet file
const wallet = JSON.parse(readFileSync("./wallet.json").toString(),);
const availableRandomValues = 44
const providerId    = "ld4ncW8yLSkckjia3cw6qO7silUdEe1nsdiEvMoLg-0"
const processId     = "6M87hnHw71bZGfDF4ZfA-UeVl369b7MoIVCXCsnETUc"
const randomTesting = "AmGZEcVGl66Wh_KB9SzY2u7SUIcRz4yUUBfvMMC5Tvc"
const tokenId       = "OeX1V1xSabUzUtNykWgu9GEaXqacBZawtK12_q5gXaA"
let providers = {
    provider_ids: ["ld4ncW8yLSkckjia3cw6qO7silUdEe1nsdiEvMoLg-0"]
}
const requestIds = [
    "9c699b01-177f-43e0-9bee-217f8f5d4b78"
]

const requestInputs     = 1
const requestId         = "8ff494d1-241d-4e47-b397-cb162ffa3cde"
const callbackId        = "call me back :("
const input             = "0xd74da6f85fc5e12cdabd2afab7f17e611708b0d0d0ff231238582b174a8ca8dadf5ea47f24cf58d41e4e65941c1d59a489339fd191fe5df9bc64b4d779c012347c38c338fabbd5fc84b249771da925846ed4f2318f225c9ba421045a24b4a1917ec860e547c2d9cdd355c16ade3b66b776fe3ba3a9a5402efa1918e91226a9d8"
const modulus           = "0x2a76067268022b81726c50e087ebf56ad64ed6154fc16aabd93374884a2d55454ed1274fb0a2ce9b1e5554db4f1e4b6ace68916bc812d03af76632848ce56fbb3e075e5bc10f48d464bd203129ddeb6e0f0a131ff86a8bdd8f4175f484556ee79973aa68d516eb0070268efdd8bdc218a36072598a3e4f8a096e75363de87e8464cf8c12f58cc1e788f8b4a4ad0d13c6deb606490ad1f99efde61f5a0efaf8cb746c18e0301bf07e749be3ec8ec5c8797af0f87abfc3707c29363ca9d3156be982d29060674ae8bb1a36fcdca65269978f9e28c7d87b69b722be1eba754276893e6a40c969ada9fed1226b4bf6c9a0158c977a1a07ba1f62d718354dcd26965"
const output            = "0x6c28c74259463338732c5d6ddd4a9b8ee87c265e4fe9b7d9273a6e535a38027f9f73bae815457fbcc03f2bcf331cb81291df793106194543553332033a5f997238b93fa99bb2c373d38ee079d7250f5e09986539d715563cdf28c1bfba2ba7fbb20160242d2db8676fdad5525154fe1c74cd11f4e6f87ab353bc8cd2f5682654c3b8b0e5db9fd7f312531bf2224de404b9ff16568fa38c842d6745918fedc7dc5dbb435bd305e23c459a78f395c4f4de83f843ca8c879ba68a4b9e6ddc1d912880aff86c9c83554aa78a9b3b38b70d6aab09c8cd5cdaabd5321c277952c280363dea4075c1ed7c88b08ebd6abdf2de32ed0cae290c08d3b96ee57ff4f1b5b7"
const proof             = JSON.stringify([
    "0x9dea9cd525d18af957e4eb7bd0d03f4bf2b8543a3bc6da727e6609b54ae028abfc8af97d47af9fb753b272339dd831e0efa8f4f2ad86959c6ac70c29e59f5749cfe0f13a9728fa379717306cc02e46eba2a0905f0ec1b2830354813f6e2047b7a84db9ad80559335c654d2bd0fa744747ab3d27771b98895d167ce0581264a9abf6cae75c40abf280d0312017e2f19fc06912400eb64cb7b8dff69a5fbb14dcdd3a7f12cd5431ebc20c011c8ab47bf1ce998ff8dba957ee5edec3c5a3aa984f6e5998bd577ccb6996952b9ce93987b937359042161e23d5dec1dd41ccc89fb4f998bce1b03cea2cb973c38fedde7d4bad9082a71cf9b1c458c3e5e94eae76c", 
    "0x1b96dffdbae630c3e82169a715e02b4eab0f581818fbd3a2be20cb7571f537b62cb12ad90d5d89c8c415f23ad637ed14340f26b833597cd1fdeba1b2bc76bf5393e7a16afa6780b574a9ee0ce1666bdefa2b5b8da79b4ef62c2626a258de45b6fffafdd4baec96bcc8226d2c65c511f8ca7aaa40ed1b80fff8acc9384bb761ea1664ac2aa477dcb3a8b3fb1f1e8bc9d11b437fcb405a3aa20afe2c6795e1e166351a6c2f6fdfd395b06fbcc5e20c93e04ef64e471034d5ebd4e39cb35be6b5f5f8b873ab2b1d6765f36b2134d8145a785760b58a3e13edaf3887579f712b6ea6c914417af065d7d42727c86c2604466a447b5cab118b6f9403fb28745757743", 
    "0x20820ca6714c0982901e5e29f5d3f05b31a9e923fc393bf852fdc346c4d6c1f684877bf867dc72e7afdaa87cd685fab4d3b5cdd0ee2784c97acfd96e089d9c5c598fb4c48051f14c8e3a99675e46e0d41c145457579247e7ec6b4d6f4afd68a85343be8efa9aa51e2a6a3afd05577e549d165bfb1e6da5c266cb6fdf4ea159f907a127f9259b5e18903cb9a9f5eccc843861b6d54d7836ad381dcfb9db20cc8395ab3ffa822ac8db4821f0f28b98288e1032dc5668883b5b9b9907cbf231e0274c8c1af241d1255b1b727211978a59c7c54b0b1b1d5b679a773623e8a0e9961cb47b0f6b7b4179adec86d752174a47fbe1000a21dd93b2bb653be6655080f86",
    "0x1a99a996510fbd40d1cf9616e46e29a1290183bec78693fb76bf064aeadce443d2719b4a8ef61b3fa36e9f43c697ada7a8ab9815f4f31158b89e3b315ddc8212292e3bfc30733216cb62032f2b6ea06145648c65ec863d3709a83ecf041349b504947462022267d2fd99c7b630da6e0541c9e4e7e9d3d8e703fc531880f374ad917a012f7c3ff797af0a68450ef17c86f8ee4bbee427b119961b934e3e31402af4f7ba72c47a18ff95e21cc728c90332400f763a611b913ff27b8f9cd186800fe8fc0f319ce5620808544999a10107ec703cdddc1854d0a451ec514e530ac0515c650a6ea2af4635db2ec9829c5f65bfbd03c7b43bfa6f5bad52b3d2ea77466",
    "0x23f3a087989fe8b40604d0b5362b0262f2d0d481f888fa00238de156f91b7f564bf78f953f3069219b5b2219543988f15ebd989cde88e39a481421e2455554da8f333a1957b1a15a6ed527326a58144fd3a9b959bfa3ec8d65692ed4493b799231067ac8509ed4c74ffa2d21f2cf4e4a1a9cbfd7b91acd4820008cb2790c67abeaab7eafcc47c8604106c7a8fe19bd9199799b06901cd9aa183820ec68a7aba4fa5e698053fda79d535f0d88c222f00970f17da26ebfec8d261e013eafad762adb2b5134ac9d53f2ac932b18989ddd28b23feb37526059dac6c20370848c9532959c602077b9787469de163c419f9c92c74cfb6fc81b8af121da7e3a43d9d9e", 
    "0x1c8db40a3570d444b6b6c7817a25aa523c3402878a57938499e2a4c2d5260e85532d0bc9a3bd4383405ca2393f23f81be5abaaeab11bb8c07522076250c8573c93d596537e5798c8291aa20be9e8f5a5ca55461dd1b858466d0f5f5e19a75f06769d4d05d8332cbf4489eb66fa903274146226c0e4260ef3525e5a1e0e93ca434310e652feb9a0750bd80c91895c1233b97cad20d05d49ebc89f8bb77ef88f86883073a1c09820c0827e47ce8d51c30cfe9fed9ad8ee16008743896029ef29d1a455302e25a8b58234348183f79c73e002878fc0aace627b90ff58bcfb5c494973f589ad5a6012ab3837ae7982c2ae8b162daf0fc685345ef3cb817bad48de1", 
    "0x1ad7cacbc04b5356238755fc7bfc650f1b3a641d8b1cf6e15e54209f930ce1f82e2bb04a0cae583c34cfa47884e1faff1e1a097a68e91a0815cce3b6d07906770f461690c7ce1207ad296d95922892e9cb2269587070ed7bdb9f459786997290746362a85859ebde948355e39467b75ae55e777bbaaa1f6ebf48db97a946f48f3749e899a6985213d1a1fadfe9d44d273a3b616332eec3cd5d75f5c96d5ac3ec7d40586a32ffacc49f4696c2570c3350f588387c9045206e9f294f3d848a63ce4a27f432ac11b5356c5af191cd005fdfd884178d550968b535d2c8ed75dcf9971a395a50677fe8c68df2fccce5c03ebd506bb3fa732a58af130a8c75fa6c1ba", 
    "0x9d949249a83d9e079d27cbc2428a5ae34c271a9945be48bab5c89f002ec5a4d180a10ca7ee962e00eacc4e2976ab1c87c1e15da69131c9f5020c8e06db12531bd9bb1ec961352032cd82cef9c1896f5566c84f5e23a5e5d396a6f6886e6ccedbb4d05e0ff9fde339ebcb6b0854dd4345846764e2b8cfab606e9a7557ffd24562dd0e01e593f270a397c91f3daf2190484317ebf7cce1fe017d763ed5359f5c6899588c11793b8379babc11af5f06dce2fe042f98ea79e2e45b6ac439fd854092678d18a175424807d8bf305f7a79f70ecb1bb56181cebb0b6c66c5c9cb597a90c968f1d438be266dc472f75198493e4ed6e92e1d690bf25fb18f12b4b29356", 
    "0x5dd707382bfef70464e56781cffc0591d86885c012216885d8892b197d6cbf89b35a95720bb0a3ba8c66c8e58845787e2c1c757200412e1cbbd1f5a2a2c45d87b542ee0dfcac2bf9c4f2e2652ddf433555ec9d23e064111e28a770dd09db791f5cabd8e1809ddfc9570d1ac64c4f69edfeebc88dcec22a7ca476e81d520cc54793846853ec383c722e094ca514094d0fac57f888c49cac144235c3bcebbbfc80dbc39231f56a835718f0f4c6df04c65f1eea56ec6524eefc242708fca4c46fd5c594f2a3300ed026407a5c5212000dc4453db687c6cc2ea2fbaa811fd3c39a863d493e0afda60954da9da7ac1f8b3bc16193d9d95361b490f3b544af31084a", 
    "0x6c28c74259463338732c5d6ddd4a9b8ee87c265e4fe9b7d9273a6e535a38027f9f73bae815457fbcc03f2bcf331cb81291df793106194543553332033a5f997238b93fa99bb2c373d38ee079d7250f5e09986539d715563cdf28c1bfba2ba7fbb20160242d2db8676fdad5525154fe1c74cd11f4e6f87ab353bc8cd2f5682654c3b8b0e5db9fd7f312531bf2224de404b9ff16568fa38c842d6745918fedc7dc5dbb435bd305e23c459a78f395c4f4de83f843ca8c879ba68a4b9e6ddc1d912880aff86c9c83554aa78a9b3b38b70d6aab09c8cd5cdaabd5321c277952c280363dea4075c1ed7c88b08ebd6abdf2de32ed0cae290c08d3b96ee57ff4f1b5b7"
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

async function requestRandomTester() {
    let tags = [
        { name: "Action", value: "run" },
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
    } 
}

main();