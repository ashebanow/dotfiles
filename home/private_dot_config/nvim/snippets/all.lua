---@diagnostic disable: undefined-global

return {
    s("date", t(os.date("%Y/%m/%d"))),
    s("email", t("ashebanow@gmail.com")),
    s("labmail", t("ashebanow@cattivi.com")),
    s("gh", t("github.com/ashebanow")),
    s("(", { t("("), i(1), t(")") }),
    s("[", { t("["), i(1), t("]") }),
    s("{", { t("{"), i(1), t("}") }),
    s("$", { t("$"), i(1), t("$") }),
}
