SHELL = /bin/bash

style:
	black .
	python3 -m isort .
	flake8 --exclude=.venv || true

clean-pyc:
	find . -name '*.pyc' -exec rm -f {} +
	find . -name '*.pyo' -exec rm -f {} +
	find . -name '*~' -exec rm -f {} +
	find . -name '__pycache__' -exec rm -fr {} +

clean-test:
	rm -f .coverage
	rm -f .coverage.*
	find . -name '.pytest_cache' -exec rm -fr {} +

clean: clean-pyc clean-test style
	find . -name '.my_cache' -exec rm -fr {} +
	rm -rf logs/

test: clean
	pytest . --cov=src --cov-report=html --cov-report=term-missing
