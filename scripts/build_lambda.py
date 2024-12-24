import shutil
import os
import argparse
import subprocess
import sys

def create_single_layer_package(package_name, python_version="3.10", platform="manylinux2014_x86_64"):
    """Create a single package Lambda layer."""
    layer_dir = "dist/layer"
    if os.path.exists(layer_dir):
        shutil.rmtree(layer_dir)
    os.makedirs(f"{layer_dir}/python/lib/python{python_version}/site-packages", exist_ok=True)

    subprocess.run([
        sys.executable, "-m", "pip", "install",
        package_name,
        f"--target={layer_dir}/python/lib/python{python_version}/site-packages",
        "--platform", platform,
        "--only-binary=:all:",
        "--implementation", "cp",
        "--python-version", python_version,
    ], check=True)

    for root, dirs, files in os.walk(layer_dir):
        for dir_name in dirs:
            if dir_name in ['tests', 'test', '__pycache__', 'examples']:
                shutil.rmtree(os.path.join(root, dir_name))
        for file_name in files:
            if file_name.endswith(('.pyc', '.pyo', '.c', '.h', '.html', '.txt')):
                os.remove(os.path.join(root, file_name))

    zip_name = f"dist/lambda_layer_{package_name}"
    shutil.make_archive(zip_name, "zip", layer_dir)
    shutil.rmtree(layer_dir)
    print(f"dist/lambda_layer_{package_name} size: {os.path.getsize(f'{zip_name}.zip') / (1024 * 1024):.4f} MB")


def create_lambda_package(source_file, zip_name, overwrite=False):
    """Create a Lambda package."""
    zip_path = f"dist/{zip_name}.zip"
    if os.path.exists(zip_path) and not overwrite:
        print(f"{zip_path} already exists. Use --overwrite to replace it.")
        return

    package_path = "dist/package"
    if os.path.exists(package_path):
        shutil.rmtree(package_path)
    os.makedirs(package_path)

    shutil.copy(source_file, package_path)
    shutil.make_archive(f"dist/{zip_name}", "zip", package_path)
    shutil.rmtree(package_path)

    print(f"{zip_name} size: {os.path.getsize(zip_path) / (1024 * 1024):.4f} MB")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Lambda Packaging Utility")
    parser.add_argument("--layer", help="Create a single-layer package.")
    parser.add_argument("--python-version", default="3.10", help="Specify the Python version for the layer (default: 3.10).")
    parser.add_argument("--platform", default="manylinux2014_x86_64", help="Specify the platform for the layer (default: manylinux2014_x86_64).")
    parser.add_argument("--overwrite", action="store_true", help="Overwrite existing Lambda zip files.")
    parser.add_argument("--lambda_func", choices=["function", "orchestrator", "both"], default="both",
                        help="Specify which Lambda package to create: function, orchestrator, or both.")
    args = parser.parse_args()

    if args.layer:
        package = args.layer
        create_single_layer_package(package, python_version=args.python_version, platform=args.platform)
    else:
        if args.lambda_func in ["function", "both"]:
            create_lambda_package("src/lambda_functions/lambda_function.py", "lambda_function", overwrite=args.overwrite)
        if args.lambda_func in ["orchestrator", "both"]:
            create_lambda_package("src/lambda_functions/lambda_orchestrator.py", "lambda_orchestrator", overwrite=args.overwrite)
