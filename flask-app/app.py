from flask import Flask, jsonify
import os
from kubernetes import client, config

app = Flask(__name__)

@app.route("/")
def home():
    return "Kubernetes Monitor Running!"

@app.route("/pods")
def get_pods():
    config.load_kube_config()
    v1 = client.CoreV1Api()
    pods = v1.list_pod_for_all_namespaces(watch=False)
    pod_list = [{"name": pod.metadata.name, "namespace": pod.metadata.namespace} for pod in pods.items]
    return jsonify(pod_list)

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
