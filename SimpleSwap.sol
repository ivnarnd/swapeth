// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// Interfaz mínima de un token ERC-20 para interactuar con otros contratos
interface IERC20 {
    function transferFrom(address from, address to, uint amount) external returns (bool);
    function transfer(address to, uint amount) external returns (bool);
    function balanceOf(address account) external view returns (uint);
}

// Contrato para crear un pool de intercambio simple tipo Uniswap
contract SimpleSwap {
    // Representación de un pool de liquidez entre dos tokens
    struct Pool {
        uint reserveA;                     // Reserva del primer token
        uint reserveB;                     // Reserva del segundo token
        uint totalLiquidity;              // Total de liquidez del pool
        mapping(address => uint) liquidity; // Liquidez aportada por cada usuario
    }

    // Mapeo de cada combinación de tokens a su pool respectivo
    mapping(bytes32 => Pool) internal pools;

    // Genera una clave única para cada par de tokens sin importar el orden
    function getPoolKey(address tokenA, address tokenB) internal pure returns (bytes32) {
        return tokenA < tokenB 
            ? keccak256(abi.encodePacked(tokenA, tokenB)) 
            : keccak256(abi.encodePacked(tokenB, tokenA));
    }

    // Devuelve el mínimo entre dos números
    function min(uint a, uint b) internal pure returns (uint) {
        return a < b ? a : b;
    }

    // Calcula la raíz cuadrada entera de un número (para asignar liquidez inicial)
    function sqrt(uint y) internal pure returns (uint z) {
        if (y > 3) {
            z = y;
            uint x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }

    // Permite a un usuario agregar liquidez a un par de tokens
    function addLiquidity(
        address tokenA,              // Dirección del token A
        address tokenB,              // Dirección del token B
        uint amountADesired,         // Monto deseado de token A
        uint amountBDesired          // Monto deseado de token B
    ) external returns (uint amountA, uint amountB, uint liquidity) {
        // Obtener clave única del pool
        bytes32 key = getPoolKey(tokenA, tokenB);
        Pool storage pool = pools[key];

        // Obtener reservas actuales del pool respetando el orden
        (uint reserveA, uint reserveB) = tokenA < tokenB ? (pool.reserveA, pool.reserveB) : (pool.reserveB, pool.reserveA);

        // Calcular montos adecuados a aportar manteniendo el ratio
        if (reserveA == 0 && reserveB == 0) {
            amountA = amountADesired;
            amountB = amountBDesired;
        } else {
            uint amountBOptimal = (amountADesired * reserveB) / reserveA;
            if (amountBOptimal <= amountBDesired) {
                amountA = amountADesired;
                amountB = amountBOptimal;
            } else {
                uint amountAOptimal = (amountBDesired * reserveA) / reserveB;
                require(amountAOptimal <= amountADesired, "Excessive A");
                amountA = amountAOptimal;
                amountB = amountBDesired;
            }
        }

        // Transferir los tokens desde el usuario al contrato
        IERC20(tokenA).transferFrom(msg.sender, address(this), amountA);
        IERC20(tokenB).transferFrom(msg.sender, address(this), amountB);

        // Calcular cuánta liquidez le corresponde al usuario
        if (pool.totalLiquidity == 0) {
            liquidity = sqrt(amountA * amountB); // Primer proveedor
        } else {
            liquidity = min(
                (amountA * pool.totalLiquidity) / reserveA,
                (amountB * pool.totalLiquidity) / reserveB
            );
        }

        require(liquidity > 0, "Liquidity must be positive");

        // Actualizar la liquidez del usuario y la total
        pool.liquidity[msg.sender] += liquidity;
        pool.totalLiquidity += liquidity;

        // Actualizar las reservas del pool
        if (tokenA < tokenB) {
            pool.reserveA += amountA;
            pool.reserveB += amountB;
        } else {
            pool.reserveA += amountB;
            pool.reserveB += amountA;
        }
    }
}