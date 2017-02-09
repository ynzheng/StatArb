################################################################################
## myConfig.R
## 设置
# 1. 账号、密码
# __2. 文件路径__
# __3. 需要的软件包__
# 4. 参数设置
################################################################################

bktestingProduct <- 'cu'

startDate <- '20170101'
endDate   <- '20170208'

forward_month <- 1 ## 跨期套利的区间，单位:month

################################################################################
## 从数据库提取 Tick Data
################################################################################

#---------------------------------------------------
mysql <- mysqlFetch('china_futures_HFT')
#---------------------------------------------------
colsFetch <- c("TradingDay", "UpdateTime", "UpdateMillisec"
               ,"InstrumentID", "LastPrice", "Volume", "Turnover"
               ,"BidPrice1","AskPrice1"
               , "NumericExchTime", "DeltaVolume", "DeltaTurnover")


dt <- dbGetQuery(mysql,
                 paste("SELECT", paste(colsFetch,collapse = ","), "FROM CiticPublic",
                       "WHERE LEFT(InstrumentID,2) = ", paste0("'",bktestingProduct,"'"),
                       "AND ( TradingDay BETWEEN",startDate, "AND", endDate, ")")
                 ) %>% as.data.table()

glimpse(dt)


################################################################################
## 主力合约
## 为该交易日前一个交易日的主力合约
################################################################################

#---------------------------------------------------
mysql <- mysqlFetch('china_futures_bar')
#---------------------------------------------------
colsFetch <- c('TradingDay', 'Product', 'Main_contract')

#-- 往前退一天
startDate_1d <- ChinaFuturesCalendar[which(gsub('-','',days) < startDate)][.N,gsub('-','',days)]
endDate_1d   <- ChinaFuturesCalendar[which(gsub('-','',days) < endDate)][.N,gsub('-','',days)]

mainContract <- dbGetQuery(mysql, paste(
                           "SELECT ", paste(colsFetch, collapse = ','),
                           "FROM main_contract_daily",
                           "WHERE TradingDay BETWEEN", startDate_1d,
                           "AND", endDate_1d
                           )) %>% as.data.table() %>% 
  .[grep(bktestingProduct,Product)]

u <- mainContract[, Main_contract]

v <- sapply(1:length(u), function(ii){
  temp1 <- gsub('[0-9]','', u[ii])
  temp2 <- gsub('[[:alpha:]]','', u[ii]) %>% 
    paste0(ifelse(nchar(.) == 3, '201', '20'), .) %>%
    as.yearmon(.,"%Y%m") %>% as.Date()
  
  temp <- temp2 %m+% months(forward_month) %>% as.character() %>% 
    gsub('-','',.) %>% substr(.,3,6) %>% paste0(temp1, .)
  
})

mainContract[, forward_contract := v]

################################################################################
## 交易时间的设定
################################################################################

#-------------------------------------------------------
updateF <- function(x){
  x %>%
    .[UpdateTime %between% c("21:00:00","23:59:59") |
        UpdateTime %between% c("00:00:00","00:59:59") |
        UpdateTime %between% c("09:00:00","10:14:29") |
        UpdateTime %between% c("10:30:00","11:29:29") |
        UpdateTime %between% c("13:30:00","14:59:59")]
}
#-------------------------------------------------------

mySecond <- CJ(hour = seq(0,23), minute = seq(0,59), second = rep(seq(0,59),2)) %>%
  .[,id := seq(1, .N)] %>%
  .[,UpdateTime := paste(sprintf('%02d',hour), sprintf('%02d',minute),
                         sprintf('%02d',second), sep = ":")]
night_end <- "00:59"
night_end_id <- mySecond[hour == substr(night_end,1,2) %>% as.numeric() &
                           minute == substr(night_end,4,5) %>% as.numeric()][.N,id]
day_end   <- "14:59"
day_end_id <- mySecond[hour == substr(day_end,1,2) %>% as.numeric() &
                         minute == substr(day_end,4,5) %>% as.numeric()][.N,id]

mySecond <- list(mySecond[hour >= 21],
                 mySecond[id %between% c(0, night_end_id)],
                 mySecond[id %between% c(64801,82800)],
                 mySecond[id %between% c(93601,day_end_id)]) %>%
  rbindlist() %>% updateF(.)

temp <- dt[,unique(TradingDay)]
mySecondTD <- lapply(1:length(temp), function(i){
  y <- data.table(TradingDay = temp[i],
                  UpdateTime = mySecond[,UpdateTime])
  return(y)
}) %>% rbindlist() %>% .[order(TradingDay)]

temp <- ChinaFuturesCalendar[days %between% c(as.Date(startDate, '%Y%m%d'),
                                              as.Date(endDate, '%Y%m%d'))]

mySecondTD <- merge(mySecondTD,temp, by.x = 'TradingDay', by.y = 'days') %>% 
  .[!(is.na(nights) & (!UpdateTime %between% c("08:55:00","15:30:00")))]
setcolorder(mySecondTD, c('TradingDay', 'nights', 'UpdateTime'))

################################################################################
## 填充数据
## 因为 Tick Data 经常会出现断点，
## 因此需要补齐断点的数据
## 使用 Rcpp
################################################################################

#---------------------------------------------------
cppFunction('
NumericVector na_convert(NumericVector x) {
int n = x.size();
NumericVector out(n);

for(int i = 1; i<(n+1); ++i ) {
      if (NumericVector::is_na(x[i])) {
        x[i] = x[i-1];
      }
}

return x;
}')
#---------------------------------------------------

#+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
addMissingData <- function(x){
  temp <- merge(mySecond, x, by = c("UpdateTime"), all = TRUE) %>%
    .[!duplicated(id)]
  
  temp <- list(temp[UpdateTime >= "21:00:00"], temp[UpdateTime < "21:00:00"]) %>%
    rbindlist()
  
  cols <- c("Volume", "Turnover", "BidPrice1", "AskPrice1")
  temp[, (cols) := lapply(.SD, na_convert), .SDcol = cols]
  
  temp <- temp  %>%
    .[is.na(LastPrice), LastPrice := (BidPrice1 + AskPrice1)/2] %>%   ##-- LastPrice = (bid+ask)/2
    .[is.na(DeltaVolume), ":="(
      DeltaVolume = 0,
      DeltaTurnover = 0
    )]
  
  return(temp)
}
#+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++


