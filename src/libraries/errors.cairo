mod LimitOrderError {
    fn OrderDoesNotExist() {
        panic(array!['limit order not found'])
    }
}

mod LiquidityError {
    fn ZeroLiquidity() {
        panic(array!['no liquidity'])
    }
}

mod RangeError {
    fn InRange() {
        panic(array!['in range'])
    }
}
