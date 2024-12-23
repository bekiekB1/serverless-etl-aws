import shutil
import os
import argparse
import subprocess
import sys

def create_single_layer_package(package_name, layer_name, python_version="3.10", platform="manylinux2014_x86_64"):
    """Create a single package Lambda layer."""
    if os.path.exists("layer"):
        shutil.rmtree("layer")
    os.makedirs(f"layer/python/lib/python{python_version}/site-packages", exist_ok=True)

    subprocess.run([
        sys.executable, "-m", "pip", "install",
        package_name,
        f"--target=layer/python/lib/python{python_version}/site-packages",
        "--platform", platform,
        "--only-binary=:all:",
        "--implementation", "cp",
        "--python-version", python_version,
        "--no-deps"  # Important: don't install dependencies
    ], check=True)

    for root, dirs, files in os.walk("layer"):
        for dir_name in dirs:
            if dir_name in ['tests', 'test', '__pycache__', 'examples']:
                shutil.rmtree(os.path.join(root, dir_name))
        for file_name in files:
            if file_name.endswith(('.pyc', '.pyo', '.c', '.h', '.html', '.txt')):
                os.remove(os.path.join(root, file_name))

    zip_name = f"lambda_layer_{layer_name}"
    shutil.make_archive(zip_name, "zip", "layer")

    shutil.rmtree("layer")
    print(f"{layer_name} layer size: {os.path.getsize(f'{zip_name}.zip') / (1024*1024):.2f} MB")

def create_lambda_package(overwrite=False):
    """Create a Lambda package."""
    package_path = "dist/package"
    lambda_zip_path = "dist/lambda_function.zip"

    # Overwrite check
    if os.path.exists(lambda_zip_path) and not overwrite:
        print(f"{lambda_zip_path} already exists. Use --overwrite to replace it.")
        return

    # Create package
    if os.path.exists(package_path):
        shutil.rmtree(package_path)
    os.makedirs(package_path)

    shutil.copy("src/lambda/lambda_function.py", "dist/package/")
    shutil.make_archive("dist/lambda_function", "zip", "dist/package/")
    shutil.rmtree(package_path)

    print(f"Function size: {os.path.getsize(lambda_zip_path) / (1024*1024):.4f} MB")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Lambda Packaging Utility")
    parser.add_argument("--layer", nargs=2, metavar=('PACKAGE', 'LAYER_NAME'), help="Create a single-layer package.")
    parser.add_argument("--python-version", default="3.10", help="Specify the Python version for the layer (default: 3.10).")
    parser.add_argument("--platform", default="manylinux2014_x86_64", help="Specify the platform for the layer (default: manylinux2014_x86_64).")
    parser.add_argument("--overwrite", action="store_true", help="Overwrite the existing lambda_function.zip file.")
    args = parser.parse_args()

    if args.layer:
        package, layer_name = args.layer
        create_single_layer_package(package, layer_name, python_version=args.python_version, platform=args.platform)
    else:
        create_lambda_package(overwrite=args.overwrite)
        