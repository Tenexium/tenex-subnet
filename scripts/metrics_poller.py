import time
import threading
from typing import Optional
import bittensor as bt
from web3 import Web3
from web3.contract import Contract

from data_store import ValidatorDataStore


class MetricsPoller:
    """
    Background service that polls blockchain metrics every minute.
    Stores data for 24-hour historical analysis.
    """
    
    def __init__(
        self,
        w3: Web3,
        tenexium_contract: Contract,
        subtensor: bt.subtensor,
        netuid: int,
        data_store: ValidatorDataStore,
        poll_interval_seconds: int = 60
    ):
        """
        Initialize the metrics poller.
        
        Args:
            w3: Web3 instance for Ethereum interactions
            tenexium_contract: Tenexium protocol contract instance
            subtensor: Bittensor subtensor instance (used to get endpoint)
            netuid: Network UID
            data_store: Data store instance for persisting metrics
            poll_interval_seconds: Polling interval in seconds (default: 60)
        """
        self.w3 = w3
        self.tenexium_contract = tenexium_contract
        self.subtensor_endpoint = subtensor.chain_endpoint
        self.netuid = netuid
        self.data_store = data_store
        self.poll_interval_seconds = poll_interval_seconds
        
        # Create separate subtensor instance for this thread to avoid WebSocket concurrency issues
        self.subtensor: Optional[bt.subtensor] = None
        
        self.polling_thread: Optional[threading.Thread] = None
        self.stop_event = threading.Event()
        self.running = False
    
    def start(self):
        """Start the background polling thread"""
        if self.running:
            bt.logging.warning("Metrics poller is already running")
            return
        
        self.stop_event.clear()
        self.running = True
        self.polling_thread = threading.Thread(
            target=self._polling_loop,
            daemon=True,
            name="MetricsPoller"
        )
        self.polling_thread.start()
        bt.logging.info(
            f"Metrics poller started with {self.poll_interval_seconds}s interval"
        )
    
    def stop(self):
        """Stop the background polling thread"""
        if not self.running:
            return
        
        bt.logging.info("Stopping metrics poller...")
        self.stop_event.set()
        
        if self.polling_thread:
            self.polling_thread.join(timeout=10)
        
        self.running = False
        bt.logging.info("Metrics poller stopped")
    
    def _polling_loop(self):
        """Main polling loop that runs in background thread"""
        bt.logging.info("Metrics polling loop started")
        
        try:
            # Create dedicated subtensor instance for this thread
            bt.logging.info(f"Creating dedicated subtensor connection to {self.subtensor_endpoint}")
            self.subtensor = bt.subtensor(self.subtensor_endpoint)
            bt.logging.info("Dedicated subtensor connection established")
            
            # Initial poll immediately
            self._poll_metrics()
            
            while not self.stop_event.is_set():
                try:
                    # Wait for interval or stop event
                    if self.stop_event.wait(timeout=self.poll_interval_seconds):
                        break
                    
                    # Poll metrics
                    self._poll_metrics()
                    
                    # Prune old data every 10 polls (every 10 minutes)
                    if self.data_store.get_record_count() % 10 == 0:
                        self.data_store.prune_old_data()
                    
                except Exception as e:
                    bt.logging.error(f"Error in polling loop: {e}")
                    # Continue polling even if one iteration fails
                    time.sleep(5)  # Brief pause before retry
        
        finally:
            # Clean up subtensor connection
            if self.subtensor:
                bt.logging.info("Closing dedicated subtensor connection")
                # Note: subtensor cleanup happens automatically on object destruction
                self.subtensor = None
        
        bt.logging.info("Metrics polling loop ended")
    
    def _poll_metrics(self):
        """
        Poll current metrics from blockchain and store them.
        This method fetches all necessary data for weight calculations.
        """
        try:
            if not self.subtensor:
                bt.logging.error("Subtensor not initialized in polling thread")
                return
            
            # Get Ethereum block number
            eth_block_number = self.w3.eth.get_block_number()
            
            # Get fee metrics from contract (in wei, convert to TAO)
            total_trading_fees_wei = self.tenexium_contract.functions.totalTradingFees().call()
            total_borrowing_fees_wei = self.tenexium_contract.functions.totalBorrowingFees().call()
            total_liquidity_wei = self.tenexium_contract.functions.totalLpStakes().call()
            
            total_trading_fees = float(total_trading_fees_wei) / 10**18
            total_borrowing_fees = float(total_borrowing_fees_wei) / 10**18
            total_liquidity = float(total_liquidity_wei) / 10**18
            
            # Get subnet price (using dedicated subtensor connection)
            subnet_price = float(self.subtensor.get_subnet_price(self.netuid))
            
            # Store metrics
            self.data_store.insert_metric(
                eth_block_number=eth_block_number,
                total_trading_fees=total_trading_fees,
                total_borrowing_fees=total_borrowing_fees,
                subnet_price=subnet_price,
                total_liquidity=total_liquidity
            )
            
            bt.logging.debug(
                f"Polled metrics - Block: {eth_block_number}, "
                f"Trading Fees: {total_trading_fees:.4f}, "
                f"Borrowing Fees: {total_borrowing_fees:.4f}, "
                f"Subnet Price: {subnet_price:.6f}, "
                f"Liquidity: {total_liquidity:.4f}"
            )
            
        except Exception as e:
            bt.logging.error(f"Failed to poll metrics: {e}")
            raise
    
    def get_24h_calculations(self) -> Optional[tuple[float, float]]:
        """
        Calculate daily LP reward and miner emission from 24h data.
        Uses all data points to compute accurate averages.
        
        Returns:
            Tuple of (daily_lp_reward, miner_daily_emission) or None if insufficient data
        """
        all_data = self.data_store.get_all_24h_data()
        
        if len(all_data) < 2:
            bt.logging.warning("Insufficient data for 24h calculations (need at least 2 points)")
            return None
        
        # Calculate time span
        oldest = all_data[0]
        newest = all_data[-1]
        time_span_hours = (newest['timestamp'] - oldest['timestamp']) / 3600.0
        
        # Log warning if less than ideal data span, but still proceed
        if time_span_hours < 24.0:
            bt.logging.warning(
                f"Using partial data span: {time_span_hours:.2f}h "
                f"(prefer 24h for best accuracy, but proceeding with available data)"
            )
        
        # Calculate average daily LP reward from all consecutive data point pairs
        daily_lp_rewards = []
        
        for i in range(len(all_data) - 1):
            current = all_data[i]
            next_point = all_data[i + 1]
            
            # Calculate time difference in hours
            time_diff_hours = (next_point['timestamp'] - current['timestamp']) / 3600.0
            
            if time_diff_hours <= 0:
                continue
            
            # Calculate fee differences
            trading_fees_diff = next_point['total_trading_fees'] - current['total_trading_fees']
            borrowing_fees_diff = next_point['total_borrowing_fees'] - current['total_borrowing_fees']
            
            # Normalize to 24-hour rate
            normalization_factor = 24.0 / time_diff_hours
            daily_trading_fees = trading_fees_diff * normalization_factor
            daily_borrowing_fees = borrowing_fees_diff * normalization_factor
            
            # Calculate LP reward for this interval
            # 26.25% of trading fees + 30.625% of borrowing fees
            interval_daily_lp_reward = (daily_trading_fees * 0.2625) + (daily_borrowing_fees * 0.30625)
            daily_lp_rewards.append(interval_daily_lp_reward)
        
        # Calculate average daily LP reward
        if not daily_lp_rewards:
            bt.logging.warning("No valid intervals for LP reward calculation")
            return None
        
        avg_daily_lp_reward = sum(daily_lp_rewards) / len(daily_lp_rewards)
        
        # Calculate average subnet price from all data points
        avg_subnet_price = sum(point['subnet_price'] for point in all_data) / len(all_data)
        
        # Calculate miner daily emission using average subnet price
        # 7200 blocks per day * 41% allocation to miners
        miner_daily_emission = avg_subnet_price * 7200 * 0.41
        
        bt.logging.info(
            f"24h Calculations from {len(all_data)} data points "
            f"({time_span_hours:.2f}h span): "
            f"Avg Daily LP Reward: {avg_daily_lp_reward:.6f}, "
            f"Avg Subnet Price: {avg_subnet_price:.6f}, "
            f"Miner Daily Emission: {miner_daily_emission:.6f}"
        )
        
        return avg_daily_lp_reward, miner_daily_emission
    
    def is_data_ready(self) -> bool:
        """
        Check if we have sufficient data for accurate calculations.
        Ideally we want 24 hours, but can work with at least 1 hour.
        """
        data_age = self.data_store.get_data_age_hours()
        return data_age >= 1.0
    
    def get_data_status(self) -> dict:
        """
        Get current status of data collection.
        
        Returns:
            Dictionary with status information
        """
        record_count = self.data_store.get_record_count()
        data_age_hours = self.data_store.get_data_age_hours()
        
        return {
            'running': self.running,
            'record_count': record_count,
            'data_age_hours': data_age_hours,
            'is_ready': self.is_data_ready(),
            'expected_24h_records': 1440,  # 60 minutes * 24 hours
            'coverage_percentage': min(100.0, (data_age_hours / 24.0) * 100)
        }

