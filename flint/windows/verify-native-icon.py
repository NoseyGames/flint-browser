"""Check the application's main icon in a Windows PE without executing it."""

import ctypes
from ctypes import wintypes
from pathlib import Path
import struct
import sys


def validate(executable, expected):
    kernel = ctypes.WinDLL('kernel32', use_last_error=True)
    kernel.LoadLibraryExW.argtypes = [wintypes.LPCWSTR, wintypes.HANDLE, wintypes.DWORD]
    kernel.LoadLibraryExW.restype = wintypes.HMODULE
    kernel.FindResourceW.argtypes = [wintypes.HMODULE, ctypes.c_void_p, ctypes.c_void_p]
    kernel.FindResourceW.restype = wintypes.HRSRC
    kernel.SizeofResource.argtypes = [wintypes.HMODULE, wintypes.HRSRC]
    kernel.SizeofResource.restype = wintypes.DWORD
    kernel.LoadResource.argtypes = [wintypes.HMODULE, wintypes.HRSRC]
    kernel.LoadResource.restype = wintypes.HGLOBAL
    kernel.LockResource.argtypes = [wintypes.HGLOBAL]
    kernel.LockResource.restype = ctypes.c_void_p
    kernel.FreeLibrary.argtypes = [wintypes.HMODULE]

    # LOAD_LIBRARY_AS_DATAFILE | LOAD_LIBRARY_AS_IMAGE_RESOURCE.
    module = kernel.LoadLibraryExW(str(executable.resolve()), None, 0x22)
    if not module:
        raise ctypes.WinError(ctypes.get_last_error())

    def read_resource(kind, resource_id):
        entry = kernel.FindResourceW(module, resource_id, kind)
        if not entry:
            raise ctypes.WinError(ctypes.get_last_error())
        size = kernel.SizeofResource(module, entry)
        ptr = kernel.LockResource(kernel.LoadResource(module, entry))
        if not ptr or not size:
            raise ValueError(f'Empty resource {kind}/{resource_id} in {executable.name}')
        return ctypes.string_at(ptr, size)

    try:
        # chrome_exe.rc uses the named IDR_MAINFRAME. chrome_dll_resource.h
        # defines the same symbol numerically in chrome.dll. RT_GROUP_ICON = 14.
        group_id = (ctypes.cast(ctypes.c_wchar_p('IDR_MAINFRAME'), ctypes.c_void_p)
                    if executable.suffix.lower() == '.exe' else 101)
        group = read_resource(14, group_id)
        reserved, kind, count = struct.unpack_from('<HHH', group)
        if reserved != 0 or kind != 1 or len(group) < 6 + 14 * count:
            raise ValueError(f'Invalid IDR_MAINFRAME group in {executable.name}')
        for i in range(count):
            width, height, _, _, _, _, _, icon_id = struct.unpack_from('<BBBBHHIH', group, 6 + 14 * i)
            if (width, height) == (32, 32) and read_resource(3, icon_id) == expected:
                print(f'{executable.name}: main 32 px icon matches the supplied Flint PNG')
                return
        raise ValueError(f'{executable.name}: main icon does not contain the expected 32 px Flint image')
    finally:
        kernel.FreeLibrary(module)


if __name__ == '__main__':
    expected_icon = Path(sys.argv[1]).read_bytes()
    for filename in sys.argv[2:]:
        validate(Path(filename), expected_icon)
