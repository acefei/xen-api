"""
This file is used for importing a non-".py" file as a module in unit test.
It never runs directly, so no shebang and no main()
"""
import sys
import os
from importlib import machinery, util

def import_from_file(module_name, file_path):
    """Import a file as a module"""
    loader = machinery.SourceFileLoader(module_name, file_path)
    spec = util.spec_from_loader(module_name, loader)
    assert spec
    assert spec.loader
    module = util.module_from_spec(spec)
    # Probably a good idea to add manually imported module stored in sys.modules
    sys.modules[module_name] = module
    spec.loader.exec_module(module)
    return module

def get_module(module_name, file_path):
    """get the module from a file"""
    testdir = os.path.dirname(__file__)
    print(testdir)
    return import_from_file(module_name, "{}/{}".format(testdir, file_path))