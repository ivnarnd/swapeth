import React, { useState, useEffect } from "react";
import { ethers } from "ethers";

function App() {
  const [address, setAddress] = useState(null);

  // Función para conectar MetaMask
  async function connectWallet() {
    if (window.ethereum) {
      try {
        const accounts = await window.ethereum.request({ method: "eth_requestAccounts" });
        setAddress(accounts[0]);
      } catch (error) {
        console.error("Usuario rechazó la conexión");
      }
    } else {
      alert("Por favor instala MetaMask");
    }
  }

  // Función para desconectar (simplemente limpiar estado)
  function disconnect() {
    setAddress(null);
  }

  return (
    <div style={{ padding: "20px" }}>
      {address ? (
        <>
          <p>Conectado como: {address}</p>
          <button onClick={disconnect}>Desconectar</button>
        </>
      ) : (
        <button onClick={connectWallet}>Conectar MetaMask</button>
      )}
    </div>
  );
}

export default App;
