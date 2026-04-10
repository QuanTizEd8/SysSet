FROM condaforge/miniforge3
RUN printf '#!/bin/bash\necho "$1" > /tmp/post-env-ran\n' > /tmp/post-env.sh \
 && chmod +x /tmp/post-env.sh
