# 🌀 RandAO: Verifiable Random Number Generation Protocol

**RandAO** is a secure, decentralized random number generation (RNG) protocol built as an AO blockchain process. Designed to eliminate bias and manipulation, RandAO ensures randomness by leveraging multiple participants in the process, each contributing entropy in a transparent and verifiable way.

## 🌐 How It Works

At the core of RandAO is a **multi-party commit-and-reveal scheme** that ensures the integrity and unpredictability of the generated random numbers.

1. **Hash Commitment Phase**:  
   All **randomness providers** submit a hashed version of their input. These commitments are collected without revealing the actual inputs.

2. **Reveal Phase**:  
   After all providers commit, each reveals their original input. These inputs are hashed again to verify the correctness of the commitments.

3. **Final Random Number Generation**:  
   Once all inputs are verified, the revealed values are **hashed together** to produce the final, verifiably random number.

This process guarantees:
- **Unpredictability**: The random output is unknown until all inputs are revealed.
- **Transparency**: Anyone can audit the process to verify that no input was tampered with.
- **Decentralization**: Multiple participants provide entropy, ensuring no single entity controls the outcome.

---

## 🔒 Security Model

RandAO uses a **commit-and-reveal scheme** to protect against premature revelation or tampering. The final random number is based on the hashed combination of all revealed inputs, ensuring:

- **Resistance to Bias**: No single participant can influence the result.
- **Verifiability**: Anyone can verify that the inputs match the original commitments.
- **Tamper-Proof Execution**: The process leverages AO’s secure, message-based environment to ensure fair coordination between participants.

---

## 💼 Use Cases

RandAO is ideal for applications requiring secure randomness, such as:

- **Lotteries and Raffles**: Fair prize distribution without bias.
- **Gaming**: Randomized in-game events or loot drops.
- **Governance**: Random selection of committees or jury members.
- **Decentralized Systems**: Any protocol needing unbiased, transparent randomness.

---

## 🎯 Why RandAO?

- **Verifiably Random**: Uses cryptographic commitments to ensure fairness.
- **Decentralized**: Multiple participants generate randomness collaboratively.
- **Lightweight**: Seamlessly integrated with AO’s message-based processes.

---

## 👥 Contributing

This is just the beginning of RandAO! We welcome contributions to expand and refine the protocol. If you’d like to get involved:
1. Fork the repository  
2. Create a feature branch  
3. Submit a pull request with detailed notes

---

## 📜 License

RandAO is released under the MIT License. See the [LICENSE](./LICENSE) file for more details.

---

## 📧 Contact

Feel free to open an issue if you have questions or ideas!

---
