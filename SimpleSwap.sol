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
        require(IERC20(tokenA).transferFrom(msg.sender, address(this), amountA), "Transfer tokenA failed");
        require(IERC20(tokenB).transferFrom(msg.sender, address(this), amountB), "Transfer tokenB failed");
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
    //Remover la liquidez
    function removeLiquidity(
    address tokenA,
    address tokenB,
    uint liquidity,
    uint amountAMin,
    uint amountBMin,
    address to,
    uint deadline
) external returns (uint amountA, uint amountB) {
    require(block.timestamp <= deadline, "Transaction expired");

    bytes32 key = getPoolKey(tokenA, tokenB);
    Pool storage pool = pools[key];

    uint userLiquidity = pool.liquidity[msg.sender];
    require(userLiquidity >= liquidity, "Not enough liquidity");

    // Obtener reservas actuales respetando el orden
    (uint reserveA, uint reserveB) = tokenA < tokenB 
        ? (pool.reserveA, pool.reserveB) 
        : (pool.reserveB, pool.reserveA);

    // Calcular cantidad a retirar proporcional a la liquidez quemada
    amountA = (liquidity * reserveA) / pool.totalLiquidity;
    amountB = (liquidity * reserveB) / pool.totalLiquidity;

    require(amountA >= amountAMin, "Amount A less than minimum");
    require(amountB >= amountBMin, "Amount B less than minimum");

    // Actualizar la liquidez del usuario y total del pool
    pool.liquidity[msg.sender] -= liquidity;
    pool.totalLiquidity -= liquidity;

    // Actualizar reservas según orden de tokens
    if (tokenA < tokenB) {
        pool.reserveA -= amountA;
        pool.reserveB -= amountB;
    } else {
        pool.reserveA -= amountB;
        pool.reserveB -= amountA;
    }

    // Transferir tokens al destinatario
    require(IERC20(tokenA).transfer(to, amountA), "Transfer of tokenA failed");
    require(IERC20(tokenB).transfer(to, amountB), "Transfer of tokenB failed");
}

function swapExactTokensForTokens(
    uint amountIn,
    uint amountOutMin,
    address[] calldata path,
    address to,
    uint deadline
) external returns (uint[] memory amounts) {
    // Solo permitimos swaps entre dos tokens (por ahora)
    require(path.length == 2, "Only 2-token swap allowed");

    // Rechazamos la transacción si ya expiró
    require(block.timestamp <= deadline, "Swap expired");

    address tokenIn = path[0];
    address tokenOut = path[1];
    bytes32 key = getPoolKey(tokenIn, tokenOut);
    Pool storage pool = pools[key];

    // Obtenemos las reservas actuales del pool (en orden)
    (uint reserveIn, uint reserveOut) = tokenIn < tokenOut
        ? (pool.reserveA, pool.reserveB)
        : (pool.reserveB, pool.reserveA);

    // Nos aseguramos de que haya liquidez en el par
    require(reserveIn > 0 && reserveOut > 0, "No liquidity in pool");

    // Transferimos los tokens de entrada desde el usuario al contrato
    require(IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn), "TokenIn transfer failed");

    // Calculamos el monto a entregar con la fórmula de Uniswap (con 0.3% de fee)
    uint amountInWithFee = amountIn * 997;
    uint numerator = amountInWithFee * reserveOut;
    uint denominator = (reserveIn * 1000) + amountInWithFee;
    uint amountOut = numerator / denominator;

    // Validamos que el usuario reciba al menos lo mínimo esperado
    require(amountOut >= amountOutMin, "Output too low");

    // Actualizamos las reservas del pool según el orden de los tokens
    if (tokenIn < tokenOut) {
        pool.reserveA += amountIn;
        pool.reserveB -= amountOut;
    } else {
        pool.reserveA -= amountOut;
        pool.reserveB += amountIn;
    }

    // Transferimos los tokens de salida al destinatario
    require(IERC20(tokenOut).transfer(to, amountOut), "TokenOut transfer failed");

    // Devolvemos las cantidades involucradas en el swap
    amounts = new uint256[](2);
    amounts[0] = amountIn;
    amounts[1] = amountOut;
}

function getPrice(address tokenA, address tokenB) external view returns (uint price) {
    // Obtenemos la clave del pool según el par de tokens
    bytes32 key = getPoolKey(tokenA, tokenB);
    Pool storage pool = pools[key];

    // Obtenemos las reservas en el orden correcto
    (uint reserveA, uint reserveB) = tokenA < tokenB
        ? (pool.reserveA, pool.reserveB)
        : (pool.reserveB, pool.reserveA);

    // Si no hay liquidez, el precio es cero
    if (reserveA == 0 || reserveB == 0) {
        return 0;
    }

    // Calculamos el precio: cuántos tokenB vale 1 tokenA
    price = (reserveB * 1e18) / reserveA;
}

function getAmountOut(
    uint amountIn,
    uint reserveIn,
    uint reserveOut
) external pure returns (uint amountOut) {
    require(amountIn > 0, "amountIn must be > 0");
    require(reserveIn > 0 && reserveOut > 0, "Invalid reserves");

    uint amountInWithFee = amountIn * 997; // Fee 0.3% para beneficiar a las cuentas que aportan liquidez
    uint numerator = amountInWithFee * reserveOut;
    uint denominator = (reserveIn * 1000) + amountInWithFee;
    amountOut = numerator / denominator;
}

}