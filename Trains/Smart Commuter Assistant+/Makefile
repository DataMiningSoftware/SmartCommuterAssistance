.PHONY: help install install-dev lint format test train generate docker-build docker-run

help:
	@echo "Targets: install, install-dev, lint, format, test, train, generate, docker-build, docker-run"

install:
	python -m pip install --upgrade pip
	pip install -r requirements.txt

install-dev:
	python -m pip install --upgrade pip
	pip install -r requirements.txt
	pip install -r requirements-dev.txt

lint:
	black --check .
	flake8 .

format:
	black .

test:
	pytest -q

train:
	python lib/PythonScript/train_crowd_model.py --input lib/PythonScript/simulated_crowd_data.csv --output lib/PythonScript/crowd_predictor.pkl

generate:
	python lib/PythonScript/generate_crowd_data.py --rows 10000 --output lib/PythonScript/simulated_crowd_data.csv

docker-build:
	docker build -t sca-python-worker -f docker/python-worker/Dockerfile .

docker-run:
	docker run --rm -e SUPABASE_URL=$$SUPABASE_URL -e SUPABASE_SERVICE_KEY=$$SUPABASE_SERVICE_KEY sca-python-worker
