# Use the official Python 3.12 image from Docker Hub
FROM python:3.12-slim

# Set the working directory inside the container
WORKDIR /app

# Copy the current directory contents into the container at /app
COPY . /app

# Install any dependencies from requirements.txt
RUN pip install --no-cache-dir -r requirements.txt

# Expose port 80 for the application
EXPOSE 80

# Command to run the app
CMD ["python", "app.py"]
