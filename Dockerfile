# An integration test & dev container which builds and installs RAPIDS from latest source branches
ARG CUDA_VERSION=10.0
ARG LINUX_VERSION=ubuntu18.04
FROM nvidia/cuda:${CUDA_VERSION}-devel-${LINUX_VERSION} as RAPIDS-BASE
ENV LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/usr/local/cuda/lib64:/usr/local/lib
# Needed for promptless tzdata install
ENV DEBIAN_FRONTEND=noninteractive

ARG CC=7
ARG CXX=7
RUN apt update -y --fix-missing && \
    apt upgrade -y && \
      apt install -y \
      git \
      gcc-${CC} \
      g++-${CXX} \
      tzdata \
      locales \
      openjdk-8-jdk \
      vim

ADD Miniconda3-latest-Linux-x86_64.sh /miniconda.sh
RUN sh /miniconda.sh -b -p /conda && /conda/bin/conda update -n base conda
ENV PATH=${PATH}:/conda/bin
# Enables "source activate conda"
SHELL ["/bin/bash", "-c"]

# Build cuDF conda env
ENV CONDA_ENV=rapids
ADD conda /conda/environments
RUN conda env create --name ${CONDA_ENV} --file /conda/environments/rapids_dev.yml
ENV LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/conda/envs/${CONDA_ENV}/lib

RUN source activate ${CONDA_ENV} && conda env update --name ${CONDA_ENV} -f=/conda/environments/useful_packages.yml

ENV PYNI_PATH=/conda/envs/${CONDA_ENV}
ENV PYTHON_VERSION=3.7
RUN locale-gen en_US.UTF-8
ENV LANG en_US.UTF-8
ENV LANGUAGE en_US:en
ENV LC_ALL en_US.UTF-8
ENV CC=/usr/bin/gcc-${CC}
ENV CXX=/usr/bin/g++-${CXX}

# Start of RAPIDS project build sections
FROM RAPIDS-BASE as CUSTRINGS

ADD rmm /rmm
WORKDIR /rmm
RUN source activate ${CONDA_ENV} && \
    mkdir build && \
    cd build && \
    cmake .. -DCMAKE_INSTALL_PREFIX=${CONDA_PREFIX} && \
    make -j install && \
    cd /rmm/python && \
    python setup.py install

# custrings
ADD custrings/LICENSE /custrings/LICENSE
ADD custrings/cpp /custrings/cpp
#ADD custrings/thirdparty /custrings/thirdparty
ENV CMAKE_CXX11_ABI=ON
RUN source activate ${CONDA_ENV} && \
    mkdir -p /custrings/cpp/build && \
    cd /custrings/cpp/build && \
    cmake .. -DCMAKE_INSTALL_PREFIX=${CONDA_PREFIX} \
             -DCMAKE_CXX11_ABI=ON \
             -DRMM_INCLUDE=/rmm/include && \ 
    make -j install
ADD custrings/python /custrings/python
WORKDIR /custrings/python
RUN source activate ${CONDA_ENV} && python setup.py install
ADD custrings/docs /custrings/docs

FROM CUSTRINGS as CUDF

# cudf
ADD cudf/thirdparty /cudf/thirdparty
ADD cudf/cpp /cudf/cpp
ADD cudf/build.sh /cudf/build.sh
WORKDIR /cudf
RUN source activate ${CONDA_ENV} && bash /cudf/build.sh libcudf
ADD cudf/python /cudf/python
ADD cudf/.git /cudf/.git
WORKDIR /cudf/python/cudf/
RUN source activate ${CONDA_ENV} && bash /cudf/build.sh cudf
#RUN source activate ${CONDA_ENV} && \
#    python setup.py build_ext --inplace && \
#    python setup.py install
ADD dask-cuda /dask-cuda
WORKDIR /dask-cuda
RUN source activate ${CONDA_ENV} && python setup.py install
WORKDIR /cudf/python/dask_cudf/
RUN source activate ${CONDA_ENV} && bash /cudf/build.sh dask_cudf
#RUN source activate ${CONDA_ENV} && python setup.py install
ADD cudf/docs /cudf/docs

# xgboost
#FROM CUDF as XGBOOST
ADD xgboost /xgboost
WORKDIR /xgboost
RUN source activate ${CONDA_ENV} && \
    mkdir -p /xgboost/build && cd /xgboost/build && \
    cmake .. -DCMAKE_INSTALL_PREFIX=$CONDA_PREFIX \
          -DCMAKE_C_COMPILER=${CC} -DCMAKE_CXX_COMPILER=${CXX} \
          -DUSE_CUDF=ON -DCMAKE_CXX11_ABI=ON \
          -DUSE_CUDA=ON -DUSE_NCCL=ON && \
    make -j install && \
    cd /xgboost/python-package && \
    python setup.py bdist_wheel && \
    python setup.py install
    #pip install /xgboost/python-package/dist/xgboost*.whl

ADD dask-xgboost /dask-xgboost
WORKDIR /dask-xgboost
RUN source activate ${CONDA_ENV} && python setup.py install

# cuml
#FROM CUDF as CUML
#ADD cuml /cuml
RUN git clone https://github.com/rapidsai/cuml /cuml --recurse-submodules
#ADD cuml/thirdparty /cuml/thirdparty
#ADD cuml/cpp /cuml/cpp
#ADD cuml/build.sh /cuml/build.sh
#ADD cuml/.git /cuml/.git

#RUN git clone https://github.com/fmtlib/fmt /fmt
#WORKDIR /fmt/build
#RUN source activate ${CONDA_ENV} && cmake .. && make install

WORKDIR /cuml
RUN source activate ${CONDA_ENV} && bash build.sh libcuml
#RUN source activate ${CONDA_ENV} && \
#    mkdir build && \
#    cd build && \
#    cmake .. -DCMAKE_INSTALL_PREFIX=$CONDA_PREFIX && \
#    make -j && \
#    make install
#ADD cuml/python /cuml/python
RUN source activate ${CONDA_ENV} && bash build.sh cuml
#RUN source activate ${CONDA_ENV} && \
#    python setup.py build_ext --inplace && \
#    python setup.py install && \
#    python -c "import cuml; print('cuML JIT compiled..')"
#ADD cuml/docs /cuml/docs

# cugraph
FROM CUDF as CUGRAPH
ADD cugraph/thirdparty /cugraph/thirdparty
ADD cugraph/cpp /cugraph/cpp
ADD cugraph/build.sh /cugraph/build.sh
WORKDIR /cugraph
#RUN source activate ${CONDA_ENV} && bash build.sh libcugraph
ADD cugraph/python /cugraph/python
WORKDIR /cugraph/python
#RUN source activate ${CONDA_ENV} && python setup.py install
ADD cugraph/docs /cugraph/docs

#FROM CUDF as RAPIDS
WORKDIR /notebooks
CMD source activate ${CONDA_ENV} && jupyter-lab --allow-root --ip='0.0.0.0' --NotebookApp.token=''
