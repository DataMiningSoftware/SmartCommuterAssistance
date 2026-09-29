FROM python:3.11-slim

WORKDIR /app

COPY backend/requirements.txt backend/requirements.txt
RUN pip install --no-cache-dir -r backend/requirements.txt

COPY backend/ backend/
COPY scripts/train_stops_kl.csv scripts/train_stops_kl.csv
COPY app/assets/data/segment_times.json app/assets/data/segment_times.json
COPY app/assets/data/ktmb_stop_map.json app/assets/data/ktmb_stop_map.json

WORKDIR /app/backend

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
  CMD python -c "import os, urllib.request; urllib.request.urlopen('http://127.0.0.1:' + os.environ.get('PORT', '8000') + '/health', timeout=4)" || exit 1

CMD ["sh", "-c", "gunicorn main:app -k uvicorn.workers.UvicornWorker --bind 0.0.0.0:${PORT:-8000} --workers ${WEB_CONCURRENCY:-2} --timeout 60 --access-logfile - --error-logfile -"]
