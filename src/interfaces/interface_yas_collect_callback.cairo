#[starknet::interface]
trait IYASCollectCallback<TContractState> {
    fn yas_collect_callback(
        self: @TContractState,
        amount_0_collected: u256,
        amount_1_collected: u256,
        data: Array<felt252>
    );
}
