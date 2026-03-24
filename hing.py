import pygame
import socket
import time
import sys
import os

LOCK_FILE = "c:\\HELL\\myapp.lock"

def acquire_lock():
    if os.path.exists(LOCK_FILE):
        # check if the pid in the file is actually still running
        try:
            with open(LOCK_FILE, "r") as f:
                pid = int(f.read().strip())
            os.kill(pid, 0)  # signal 0 just checks if process exists
            return False  # still running
        except (OSError, ValueError):
            pass  # process is dead, stale lock
    
    with open(LOCK_FILE, "w") as f:
        f.write(str(os.getpid()))
    return True

if not acquire_lock():
    print("Already running, exiting.")
    sys.exit()

import atexit
atexit.register(lambda: os.remove(LOCK_FILE) if os.path.exists(LOCK_FILE) else None)


pygame.init()
pygame.joystick.init()

joystick = pygame.joystick.Joystick(1)
joystick.init()
    
UDP_IP = "127.0.0.1"
UDP_PORT = 7778
sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)

last_state = [0] * joystick.get_numbuttons()
last_axis = [0.0] * joystick.get_numaxes()
axis_last_sent = [0.0] * joystick.get_numaxes()
axis_pending = [False] * joystick.get_numaxes()

while True:
    pygame.event.pump()
    now = time.time()
    updatefreq = 1/120
    
    for i in range(joystick.get_numbuttons()):
        current = joystick.get_button(i)
        if current and not last_state[i]:
            sock.sendto(f"BTN_{i}_PRESSED".encode(), (UDP_IP, UDP_PORT))
            print(f"BTN_{i}_PRESSED",flush=True)
        elif not current and last_state[i]:
            sock.sendto(f"BTN_{i}_RELEASED".encode(), (UDP_IP, UDP_PORT))
            print(f"BTN_{i}_RELEASED",flush=True)
        last_state[i] = current

    for i in range(joystick.get_numaxes()):
        current = joystick.get_axis(i)
        if abs(current - last_axis[i]) > 0.001:
            last_axis[i] = current
            axis_pending[i] = True

        if axis_pending[i] and (now - axis_last_sent[i]) >= updatefreq:
            sock.sendto(f"AXIS_{i}_{current:.4f}".encode(), (UDP_IP, UDP_PORT))
            print(f"AXIS_{i}_{current:.4f}",flush=True)
            axis_last_sent[i] = now
            axis_pending[i] = False
    time.sleep(updatefreq) 