/***************************************************************************
 *   Copyright (C) 2010-2026 by Ilya Kotov                                 *
 *   forkotov02@ya.ru                                                      *
 *                                                                         *
 *   This program is free software; you can redistribute it and/or modify  *
 *   it under the terms of the GNU General Public License as published by  *
 *   the Free Software Foundation; either version 2 of the License, or     *
 *   (at your option) any later version.                                   *
 *                                                                         *
 *   This program is distributed in the hope that it will be useful,       *
 *   but WITHOUT ANY WARRANTY; without even the implied warranty of        *
 *   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the         *
 *   GNU General Public License for more details.                          *
 *                                                                         *
 *   You should have received a copy of the GNU General Public License     *
 *   along with this program; if not, write to the                         *
 *   Free Software Foundation, Inc.,                                       *
 *   51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.         *
 ***************************************************************************/

#ifndef OUTPUTNULL_H
#define OUTPUTNULL_H

#include <qmmp/output.h>
#include <QFile>

/**
    @author Ilya Kotov <forkotov02@ya.ru>
*/
class OutputNull : public Output
{
public:
    OutputNull();
    ~OutputNull();

    bool initialize(quint32, ChannelMap map, Qmmp::AudioFormat format) override;
    //output api
    qint64 latency() override;
    qint64 writeAudio(unsigned char *data, qint64 maxSize) override;
    void drain() override;
    void reset() override;

private:
    qint64 m_bytes_per_second = 0;
    QFile capture_;
};


#endif // OutputNull_H
