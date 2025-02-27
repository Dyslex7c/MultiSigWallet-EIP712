import React, { useState, useEffect } from 'react';
import Web3 from 'web3';

const MultiSigWallet = () => {
  const [web3, setWeb3] = useState(null);
  const [account, setAccount] = useState('');
  const [transaction, setTransaction] = useState(null);
  const [signature, setSignature] = useState('');
  const [walletContract, setWalletContract] = useState(null);
  const [walletAddress, setWalletAddress] = useState('');
  const [chainId, setChainId] = useState('');
  const [pendingTransactions, setPendingTransactions] = useState([]);

  // Sample form state for creating transactions
  const [recipient, setRecipient] = useState('');
  const [amount, setAmount] = useState('');
  const [description, setDescription] = useState('');

  useEffect(() => {
    const initWeb3 = async () => {
      if (window.ethereum) {
        try {
          const web3Instance = new Web3(window.ethereum);
          await window.ethereum.request({ method: 'eth_requestAccounts' });
          const accounts = await web3Instance.eth.getAccounts();
          const chainIdHex = await web3Instance.eth.getChainId();
          
          setWeb3(web3Instance);
          setAccount(accounts[0]);
          setChainId(chainIdHex);
          
          // Initialize contract with ABI and address
          // This would be replaced with your deployed contract address
          const contractAddress = '0x...'; // Replace with your contract address
          const contractABI = ["a"]; // Replace with your contract ABI
          
          const contract = new web3Instance.eth.Contract(contractABI, contractAddress);
          setWalletContract(contract);
          setWalletAddress(contractAddress);

          // Load pending transactions
          if (contract) {
            loadPendingTransactions(contract);
          }
        } catch (error) {
          console.error("Error initializing web3", error);
        }
      } else {
        alert("Please install MetaMask to use this application");
      }
    };

    initWeb3();
  }, []);

  const loadPendingTransactions = async (contract) => {
    try {
      // This would call a method on your contract to get pending transactions
      const count = await contract.methods.getTransactionCount().call();
      const transactions = [];
      
      for (let i = 0; i < count; i++) {
        const tx = await contract.methods.getTransaction(i).call();
        if (!tx.executed) {
          transactions.push({
            id: i,
            to: tx.to,
            value: web3.utils.fromWei(tx.value, 'ether'),
            description: tx.description,
            approvals: tx.approvalCount,
            executed: tx.executed
          });
        }
      }
      
      setPendingTransactions(transactions);
    } catch (error) {
      console.error("Error loading transactions", error);
    }
  };

  const createTransactionRequest = async () => {
    if (!recipient || !amount || !description) {
      alert("Please fill all fields");
      return;
    }

    try {
      const txObject = {
        to: recipient,
        value: web3.utils.toWei(amount, 'ether'),
        data: '0x', // For simple ETH transfers
        description: description,
        nonce: Date.now() // Using timestamp as nonce for simplicity
      };

      setTransaction(txObject);

      // Create and sign the typed data
      const signature = await signTransaction(txObject);
      setSignature(signature);

      return { ...txObject, signature };
    } catch (error) {
      console.error("Error creating transaction request", error);
    }
  };

  const signTransaction = async (txObject) => {
    const domain = {
      name: "MultiSig-Wallet",
      version: "1",
      verifyingContract: walletAddress,
      chainId: chainId
    };

    const types = {
      Transaction: [
        { name: "to", type: "address" },
        { name: "value", type: "uint256" },
        { name: "data", type: "bytes" },
        { name: "description", type: "string" },
        { name: "nonce", type: "uint256" }
      ]
    };

    const typedData = {
      types: {
        EIP712Domain: [
          { name: "name", type: "string" },
          { name: "version", type: "string" },
          { name: "chainId", type: "uint256" },
          { name: "verifyingContract", type: "address" }
        ],
        ...types
      },
      primaryType: "Transaction",
      domain,
      message: txObject
    };

    try {
      const result = await window.ethereum.request({
        method: "eth_signTypedData_v4",
        params: [account, JSON.stringify(typedData)]
      });

      return result;
    } catch (error) {
      console.error("Error signing transaction", error);
      throw error;
    }
  };

  const submitTransaction = async () => {
    if (!transaction || !signature) {
      alert("Please create a transaction first");
      return;
    }

    try {
      // Submit transaction with signature to the contract
      await walletContract.methods.submitTransaction(
        transaction.to,
        transaction.value,
        transaction.data,
        transaction.description,
        transaction.nonce,
        signature
      ).send({ from: account });

      // Reset form after submission
      setRecipient('');
      setAmount('');
      setDescription('');
      setTransaction(null);
      setSignature('');

      // Reload pending transactions
      loadPendingTransactions(walletContract);
    } catch (error) {
      console.error("Error submitting transaction", error);
    }
  };

  const approveTransaction = async (txId) => {
    try {
      await walletContract.methods.approveTransaction(txId).send({ from: account });
      loadPendingTransactions(walletContract);
    } catch (error) {
      console.error("Error approving transaction", error);
    }
  };

  const executeTransaction = async (txId) => {
    try {
      await walletContract.methods.executeTransaction(txId).send({ from: account });
      loadPendingTransactions(walletContract);
    } catch (error) {
      console.error("Error executing transaction", error);
    }
  };

  return (
    <div className="container mx-auto p-4">
      <h1 className="text-2xl font-bold mb-4">Multi-Signature Wallet</h1>
      
      {account ? (
        <div className="mb-4">Connected Account: {account}</div>
      ) : (
        <div className="mb-4">Please connect your wallet</div>
      )}

      <div className="bg-gray-100 p-4 rounded-lg mb-6">
        <h2 className="text-xl font-semibold mb-3">Create New Transaction</h2>
        <div className="mb-3">
          <label className="block mb-1">Recipient Address:</label>
          <input
            type="text"
            value={recipient}
            onChange={(e) => setRecipient(e.target.value)}
            className="w-full p-2 border rounded"
            placeholder="0x..."
          />
        </div>
        <div className="mb-3">
          <label className="block mb-1">Amount (ETH):</label>
          <input
            type="text"
            value={amount}
            onChange={(e) => setAmount(e.target.value)}
            className="w-full p-2 border rounded"
            placeholder="0.1"
          />
        </div>
        <div className="mb-3">
          <label className="block mb-1">Description:</label>
          <input
            type="text"
            value={description}
            onChange={(e) => setDescription(e.target.value)}
            className="w-full p-2 border rounded"
            placeholder="Payment for services"
          />
        </div>
        <div className="flex space-x-2">
          <button
            onClick={createTransactionRequest}
            className="bg-blue-500 text-white px-4 py-2 rounded hover:bg-blue-600"
          >
            Sign Transaction
          </button>
          <button
            onClick={submitTransaction}
            className="bg-green-500 text-white px-4 py-2 rounded hover:bg-green-600"
            disabled={!transaction || !signature}
          >
            Submit Transaction
          </button>
        </div>
      </div>

      {signature && (
        <div className="bg-gray-100 p-4 rounded-lg mb-6">
          <h3 className="font-semibold mb-2">Transaction Signed:</h3>
          <pre className="bg-gray-200 p-2 rounded overflow-x-auto">
            {JSON.stringify({ transaction, signature }, null, 2)}
          </pre>
        </div>
      )}

      <div className="bg-gray-100 p-4 rounded-lg">
        <h2 className="text-xl font-semibold mb-3">Pending Transactions</h2>
        {pendingTransactions.length > 0 ? (
          <div className="space-y-4">
            {pendingTransactions.map((tx) => (
              <div key={tx.id} className="border p-3 rounded bg-white">
                <div><strong>ID:</strong> {tx.id}</div>
                <div><strong>To:</strong> {tx.to}</div>
                <div><strong>Amount:</strong> {tx.value} ETH</div>
                <div><strong>Description:</strong> {tx.description}</div>
                <div><strong>Approvals:</strong> {tx.approvals}</div>
                <div className="mt-2 flex space-x-2">
                  <button
                    onClick={() => approveTransaction(tx.id)}
                    className="bg-blue-500 text-white px-3 py-1 rounded text-sm hover:bg-blue-600"
                  >
                    Approve
                  </button>
                  <button
                    onClick={() => executeTransaction(tx.id)}
                    className="bg-green-500 text-white px-3 py-1 rounded text-sm hover:bg-green-600"
                  >
                    Execute
                  </button>
                </div>
              </div>
            ))}
          </div>
        ) : (
          <div>No pending transactions</div>
        )}
      </div>
    </div>
  );
};

export default MultiSigWallet;