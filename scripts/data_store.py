import sqlite3
import time
import threading
from pathlib import Path
from typing import Optional, Tuple
import bittensor as bt


class ValidatorDataStore:
    """
    Time-series data store for validator metrics.
    Stores 24-hour historical data for accurate daily calculations.
    """
    
    def __init__(self, db_path: str = "validator_data.db"):
        """
        Initialize the data store.
        
        Args:
            db_path: Path to SQLite database file
        """
        self.db_path = Path(db_path)
        self.connection: Optional[sqlite3.Connection] = None
        self.lock = threading.Lock()
        self._initialize_database()
    
    def _initialize_database(self):
        """Create database tables if they don't exist"""
        with self.lock:
            self.connection = sqlite3.connect(self.db_path, check_same_thread=False)
            cursor = self.connection.cursor()
            
            # Create metrics table with indexed timestamp
            cursor.execute("""
                CREATE TABLE IF NOT EXISTS metrics (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    timestamp INTEGER NOT NULL,
                    eth_block_number INTEGER NOT NULL,
                    total_trading_fees REAL NOT NULL,
                    total_borrowing_fees REAL NOT NULL,
                    subnet_price REAL NOT NULL,
                    total_liquidity REAL NOT NULL
                )
            """)
            
            # Create index on timestamp for efficient queries
            cursor.execute("""
                CREATE INDEX IF NOT EXISTS idx_timestamp 
                ON metrics(timestamp)
            """)
            
            self.connection.commit()
            bt.logging.info(f"Database initialized at {self.db_path}")
    
    def insert_metric(
        self,
        eth_block_number: int,
        total_trading_fees: float,
        total_borrowing_fees: float,
        subnet_price: float,
        total_liquidity: float
    ):
        """
        Insert a new metric record.
        
        Args:
            eth_block_number: Current Ethereum block number
            total_trading_fees: Total accumulated trading fees
            total_borrowing_fees: Total accumulated borrowing fees
            subnet_price: Current subnet price
            total_liquidity: Total LP stakes
        """
        with self.lock:
            cursor = self.connection.cursor()
            timestamp = int(time.time())
            
            cursor.execute("""
                INSERT INTO metrics (
                    timestamp,
                    eth_block_number,
                    total_trading_fees,
                    total_borrowing_fees,
                    subnet_price,
                    total_liquidity
                ) VALUES (?, ?, ?, ?, ?, ?)
            """, (
                timestamp,
                eth_block_number,
                total_trading_fees,
                total_borrowing_fees,
                subnet_price,
                total_liquidity
            ))
            
            self.connection.commit()
            bt.logging.debug(
                f"Inserted metric at timestamp {timestamp}, "
                f"block {eth_block_number}"
            )
    
    def get_24h_data(self) -> Optional[Tuple[dict, dict]]:
        """
        Get oldest and newest data points within the last 24 hours.
        
        Returns:
            Tuple of (oldest_data, newest_data) dictionaries, or None if insufficient data
        """
        with self.lock:
            cursor = self.connection.cursor()
            current_time = int(time.time())
            time_24h_ago = current_time - (24 * 60 * 60)
            
            # Get oldest record in 24h window
            cursor.execute("""
                SELECT 
                    timestamp,
                    eth_block_number,
                    total_trading_fees,
                    total_borrowing_fees,
                    subnet_price,
                    total_liquidity
                FROM metrics
                WHERE timestamp >= ?
                ORDER BY timestamp ASC
                LIMIT 1
            """, (time_24h_ago,))
            
            oldest = cursor.fetchone()
            if not oldest:
                bt.logging.warning("No data available in 24h window")
                return None
            
            # Get newest record
            cursor.execute("""
                SELECT 
                    timestamp,
                    eth_block_number,
                    total_trading_fees,
                    total_borrowing_fees,
                    subnet_price,
                    total_liquidity
                FROM metrics
                ORDER BY timestamp DESC
                LIMIT 1
            """)
            
            newest = cursor.fetchone()
            if not newest:
                return None
            
            # Convert to dictionaries
            keys = [
                'timestamp',
                'eth_block_number',
                'total_trading_fees',
                'total_borrowing_fees',
                'subnet_price',
                'total_liquidity'
            ]
            
            oldest_data = dict(zip(keys, oldest))
            newest_data = dict(zip(keys, newest))
            
            return oldest_data, newest_data
    
    def get_data_age_hours(self) -> float:
        """
        Get the age of the data collection in hours.
        
        Returns:
            Hours of data available, or 0 if no data
        """
        with self.lock:
            cursor = self.connection.cursor()
            
            cursor.execute("""
                SELECT MIN(timestamp), MAX(timestamp)
                FROM metrics
            """)
            
            result = cursor.fetchone()
            if not result or not result[0]:
                return 0.0
            
            min_time, max_time = result
            return (max_time - min_time) / 3600.0
    
    def prune_old_data(self):
        """Remove data older than 24 hours"""
        with self.lock:
            cursor = self.connection.cursor()
            current_time = int(time.time())
            time_24h_ago = current_time - (24 * 60 * 60)
            
            cursor.execute("""
                DELETE FROM metrics
                WHERE timestamp < ?
            """, (time_24h_ago,))
            
            deleted_count = cursor.rowcount
            self.connection.commit()
            
            if deleted_count > 0:
                bt.logging.debug(f"Pruned {deleted_count} old records")
    
    def get_record_count(self) -> int:
        """Get total number of records in database"""
        with self.lock:
            cursor = self.connection.cursor()
            cursor.execute("SELECT COUNT(*) FROM metrics")
            return cursor.fetchone()[0]
    
    def close(self):
        """Close database connection"""
        with self.lock:
            if self.connection:
                self.connection.close()
                bt.logging.info("Database connection closed")

