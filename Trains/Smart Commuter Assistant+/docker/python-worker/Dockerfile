FROM python:3.10-slim

WORKDIR /app

# copy requirements and install runtime deps
COPY requirements.txt requirements-dev.txt /app/
RUN python -m pip install --upgrade pip && \
    pip install --no-cache-dir -r requirements.txt

# copy project
COPY . /app

ENV PYTHONUNBUFFERED=1

CMD ["python", "lib/PythonScript/predict_and_upsert_crowd.py"]
