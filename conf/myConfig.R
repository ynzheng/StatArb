################################################################################
## 设置
# 1. 账号、密码
# 2. 文件路径
# 3. 需要的软件包
# 4. 参数设置
################################################################################



pkgs <- c("tidyverse", "data.table", "parallel",
          "RMySQL", "stringr", "bit64", "Rcpp")
##------------------------------------------------------------------------------
if(length(pkgs[!pkgs %in% installed.packages()]) != 0){
  sapply(pkgs[!pkgs %in% installed.packages()], install.packages)
}
##------------------------------------------------------------------------------
sapply(pkgs, require, character.only = TRUE)

##------------------------------------------------------------------------------
options(digits = 12, digits.secs = 6, width=120,
        datatable.verbose = FALSE, scipen = 10)
##------------------------------------------------------------------------------

MySQL(max.con = 300)
for( conns in dbListConnections(MySQL()) ){
  dbDisconnect(conns)
}
