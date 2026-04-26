docker compose up -d

docker exec -it terraform_iam_lab sh

/workspace # terraform apply

docker restart rover_visualizer

Go to http://localhost:9000/

![img_1.png](img_1.png)