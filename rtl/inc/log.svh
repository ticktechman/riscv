`ifndef INC_LOG_H
`define INC_LOG_H

`define LOGI(msg) $display("[I|%t|%m] %s", $realtime, msg)
`define LOGW(msg) $display("[W|%t|%m] %s", $realtime, msg)
`define LOGE(msg) $display("[E|%t|%m] %s", $realtime, msg)

`endif
