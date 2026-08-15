# Library for logging python code with color 
from colorama import Fore, init
import datetime
import time
import os
import traceback
import inspect
import threading
from pathlib import Path
from enum import IntEnum

class LogLevel:
    DEBUG_P = -1
    DEBUG = 0
    INFO = 1
    WARNING = 2
    ERROR = 3

class SafeDict(dict):
    def __missing__(self, key):
        return f"{{{key}}}"
    
class Logger:
    def __init__(self, colors=True, frame=50, version='test', save=False, min_level=LogLevel.INFO, days = 7, log_format="[{timestamp}] [{location}] {message}"):
        # State management
        self.log_colors = {'info': Fore.BLUE, 'debug': Fore.GREEN, 'warning': Fore.RED, 'error': Fore.RED}
        self.version = version
        self.days = days
        self.lock = threading.Lock()
        self.config = {
            'colors': colors,
            'frame': frame,
            'debug': False if version == 'full' else True,
            'save': save,
            'min_level': min_level,
            'format': log_format
        }
        
        if colors:
            init(autoreset=True)
            
        if save:
            self.base_name = Path(__file__).stem
            self.log_timestamp = datetime.datetime.now().strftime("%Y-%m-%d_%H-%M-%S")
            self.folder = f'logs/{self.base_name}'
            os.makedirs(self.folder, exist_ok=True)

            self.cleanup_old_logs(self.folder, self.days)
            self.log_file = open(f'{self.folder}/{self.base_name}_{self.log_timestamp}.txt', 'a')

    def __enter__(self):
        return self
    
    def __exit__(self, exc_type, exc_val, exc_tb):
        self.close()

    def cleanup_old_logs(self, folder, days):
        with self.lock:
            now = time.time()
            seconds_limit = days * 24 * 60 * 60
            if not os.path.exists(folder): return
            for filename in os.listdir(folder):
                path = os.path.join(folder, filename)
                if now - os.path.getmtime(path) > seconds_limit:
                    os.remove(path)

    def log(self, prefix, message, color_key, level: LogLevel):
        if self.config['min_level'] > level: return

        frame_info = inspect.stack()[2]
        data = {
            'timestamp': datetime.datetime.now().strftime("%H:%M:%S"),
            'location': f"{os.path.basename(frame_info.filename)}:{frame_info.lineno}",
            'function': frame_info.function,
            'message': message,
            'prefix': prefix
        }

        color = self.log_colors[color_key] if self.config['colors'] else ""
        frame = self.config['frame']
        line = color + ('—' * frame if frame > 0 else "")

        try:
            msg_str = self.config['format'].format_map(SafeDict(data))
        except Exception:
            msg_str = f"FORMAT ERROR: {message}"
    
        output = f"{color}| {prefix} {msg_str:<12}"

        with self.lock:
            if frame > 0: print(line)
            print(output)
            if frame > 0: print(line)

            if self.config['save']:
                self.log_file.write(f'{msg_str}\n')
                self.log_file.flush()

    def close(self):
        if self.config['save'] and not self.log_file.closed:
            self.log_file.close()

    # Logging methods
    def info(self, msg): self.log('💡 [INFO]', msg, 'info', 1)
    def debug(self, msg): 
        if self.config['debug']: self.log('🐛 [DEBUG]', msg, 'debug', 0)
    def debug_p(self, msg): 
        if self.config['debug'] and self.version == 'test_advance':  self.log('🐛 + [DEBUG]', msg, 'debug', -1) 
    def warning(self, msg): self.log('❗ [WARNING]', msg.upper(), 'warning', 2)
    def error(self, msg, exc=None):
        self.log(f'🛑 [ERROR] ', msg.upper(), 'error', 3)
        error_details = traceback.format_exc() if exc is None else "".join(traceback.format_exception(type(exc), exc, exc.__traceback__))
        print(error_details)
        if self.config['save']:
            self.log_file.write(f"--- TRACEBACK ---\n{error_details}\n-----------------\n")
            self.log_file.flush()

class Timer:
    def __init__(self, logger, task_name="Task"):
        self.logger = logger
        self.task_name = task_name
        self.start_time = None

    def __enter__(self):
        self.start_time = time.perf_counter()
        self.logger.info(f"Starting: {self.task_name}")
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        end_time = time.perf_counter()
        duration = end_time - self.start_time
        self.logger.info(f"Finished: {self.task_name} | Duration: {duration:.4f} seconds")
