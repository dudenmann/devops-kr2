# Reconstructed unsafe training baseline, not the missing teacher template.
FROM python:3.12-slim
WORKDIR /app
COPY . .
RUN pip install --no-cache-dir -r requirements.txt
EXPOSE 5000
CMD gunicorn --bind 127.0.0.1:5000 app:app
