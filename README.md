# 🌍 Decentralized Import/Export Verification

A blockchain-based smart contract system for verifying international trade transactions on the Stacks network. This contract enables secure, transparent, and decentralized verification of import/export activities with built-in dispute resolution.

## ✨ Features

- 📦 **Trade Registration**: Create and track import/export transactions
- 🔍 **Third-Party Verification**: Assign trusted verifiers to validate trades
- 📄 **Document Management**: Upload and verify trade documents
- 💰 **Stake-Based Security**: Require stakes to prevent fraudulent activities  
- ⚖️ **Dispute Resolution**: Handle trade disputes with compensation mechanisms
- 🏆 **Reputation System**: Track verifier performance and ratings
- ⏰ **Time-Based Expiry**: Automatic trade expiration for security

## 🚀 Quick Start

### Prerequisites
- Clarinet CLI installed
- Stacks wallet with STX tokens

### Installation
```bash
git clone <repository-url>
cd Decentralized-Import-Export-Verification
clarinet check
```

### Running Tests
```bash
npm install
npm test
```

## 📖 Usage Guide

### 1. Register as a Verifier 👨‍💼
```clarity
(contract-call? .Decentralized-Import-Export-Verification register-verifier u5000)
```

### 2. Create a Trade 📋
```clarity
(contract-call? .Decentralized-Import-Export-Verification create-trade 
  'SP2J6ZY48GV1EZ5V2V5RB9MP66SW86PYKKNRV9EJ7  ; importer address
  0x1234567890abcdef1234567890abcdef12345678  ; goods hash
  u100                                        ; quantity
  u50000                                      ; value in microSTX
  u2000)                                      ; stake amount
```

### 3. Assign a Verifier 🔍
```clarity
(contract-call? .Decentralized-Import-Export-Verification assign-verifier 
  u1                                          ; trade ID
  'SP1HTBVD3JG9C05J7HBJTHGR0GGW7KXW28M5JS8QE) ; verifier address
```

### 4. Upload Documents 📄
```clarity
(contract-call? .Decentralized-Import-Export-Verification upload-document
  u1                                          ; trade ID
  "invoice"                                   ; document type
  0xabcdef1234567890abcdef1234567890abcdef12) ; document hash
```

### 5. Verify Trade ✅
```clarity
(contract-call? .Decentralized-Import-Export-Verification verify-trade
  u1                                          ; trade ID
  true                                        ; verification result
  "All documents verified and goods match")   ; verification notes
```

### 6. Confirm Receipt 📥
```clarity
(contract-call? .Decentralized-Import-Export-Verification confirm-receipt u1)
```

## 🔧 Administrative Functions

### Update Minimum Stake
```clarity
(contract-call? .Decentralized-Import-Export-Verification update-min-stake u3000)
```

### Update Verification Window
```clarity
(contract-call? .Decentralized-Import-Export-Verification update-verification-window u2000)
```

## 📊 Query Functions

### Get Trade Information
```clarity
(contract-call? .Decentralized-Import-Export-Verification get-trade u1)
```

### Get Verifier Information
```clarity
(contract-call? .Decentralized-Import-Export-Verification get-verifier 'SP1HTBVD3JG9C05J7HBJTHGR0GGW7KXW28M5JS8QE)
```

### Check Trade Statistics
```clarity
(contract-call? .Decentralized-Import-Export-Verification get-trade-statistics)
```

## 💡 Trade Statuses

- **pending**: Trade created, waiting for verifier assignment
- **assigned**: Verifier assigned, waiting for verification
- **verified**: Trade successfully verified by verifier
- **rejected**: Trade rejected by verifier
- **completed**: Trade completed and receipt confirmed
- **disputed**: Trade under dispute
- **resolved**: Dispute resolved
- **cancelled**: Trade cancelled by exporter
- **emergency-withdrawn**: Emergency withdrawal by contract owner

## 🛡️ Security Features

- **Stake Requirements**: Minimum stake amounts to prevent spam
- **Time Limits**: Trades expire automatically if not completed
- **Authorization Checks**: Only authorized parties can perform actions
- **Reputation System**: Verifiers build reputation through successful verifications
- **Emergency Controls**: Contract owner can intervene in extreme cases

## ⚠️ Error Codes

- `u100`: Owner only function
- `u101`: Resource not found
- `u102`: Unauthorized access
- `u103`: Resource already exists
- `u104`: Invalid status for operation
- `u105`: Insufficient stake amount
- `u106`: Trade expired
- `u107`: Invalid verification


## 📜 License

This project is open source and available under the MIT License.
