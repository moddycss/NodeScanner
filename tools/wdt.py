# Node Scanner tools - created with the help of AI (Claude). MIT licensed.
"""Minimal reader for WoW WDT files: lists chunks and reads the MAID tile table."""
import struct, sys
def chunks(path):
    d = open(path, 'rb').read()
    i = 0
    while i + 8 <= len(d):
        tag = d[i:i+4][::-1].decode('ascii', 'replace')
        size = struct.unpack_from('<I', d, i+4)[0]
        yield tag, d[i+8:i+8+size]
        i += 8 + size

def maid(path, chunk='MAID'):
    for tag, body in chunks(path):
        if tag == chunk:
            return [struct.unpack_from('<8I', body, k*32) for k in range(4096)]


if __name__ == "__main__":
    for p in sys.argv[1:]:
        print(p)
        for tag, body in chunks(p):
            print('  ', tag, len(body))
