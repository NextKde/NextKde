#pragma once
#include <QTranslator>
#include <QFile>
#include <QJsonDocument>
#include <QJsonObject>

// All contexts use the same reviewed UI vocabulary. User metadata never passes
// through this translator; only explicit Qt translation calls do.
class UiTranslator final : public QTranslator {
public:
    UiTranslator() {
        QFile file(":/translations/en_US.json");
        if(file.open(QIODevice::ReadOnly))strings_=QJsonDocument::fromJson(file.readAll()).object();
    }
    bool isEmpty() const override {return strings_.isEmpty();}
    QString translate(const char*,const char* source,const char* = nullptr,int = -1) const override {
        return strings_.value(QString::fromUtf8(source)).toString();
    }
private:
    QJsonObject strings_;
};
