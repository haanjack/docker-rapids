docker run  -p 8888:8888 -p 8787:8787 -p 8000:8000 \
    -v /data:/data \
    -v /home/dev/projects/dev-notebooks:/notebooks \
    -it nightly
