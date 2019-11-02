/*
 2016.08.26 07:45
 LCD: RS-9; En-8; D4-7; D5-6; D6-5; D7-4.
 RTC: SDA-A4; SCL-A5.
 SD: SS(SD1)-10, MOSI(SD2)-11, MISO(SD5)-12, SCK(SD7)-13.
 Swich Mode: 3 (HIGH-Adjust; LOW-Record).
 ADC0-2 Current shunts 12.7ohm - External Currents <87mA
*/

#define _timeRecordInterval 60000 //ms 
#define _timeSwitchInterval 100 //ms 
#define _timeRTCinterval 1000 //ms 
#define _timeLCDinterval 2000 //ms 

#include "Wire.h"
#define DS1307_ADDRESS 0x68

#include <LiquidCrystal.h>
// initialize the LCD library with interface pins order
LiquidCrystal lcd(9,8,7,6,5,4);

int counter;
unsigned char second,minute,hour,weekD,day,month,year;
int LCDpage;
#define _maxLCDpage 5

#define _markLen 16
#define _marker "Kubov V.I. 2016 "
#define _sizeOffset 16

// 512-byte block format: Record#(word); 127*(word) Data  
#define _samples 255

#include "Fat16.h"
// define SDcard params
#define _blockSize 512 //fixed in Fat16 Libraries
byte Buffer[_blockSize]; 
int curPos=0;

SdCard SD;

unsigned char SDerror;
#define _SDcard 1
#define _SDfile 2
#define _SDmemory 3

#define _Switch 3
unsigned char Mode, oldMode;
#define _Adjust HIGH
#define _Record LOW
unsigned char firstString;

long SDsize=0;
long fileStart=0; long fileSize=0; long fileEnd=0;
long startBlock=0; long curBlock=0;
char Marker[_markLen+1]=_marker;
unsigned int curRecord=0xFFFF;

unsigned long nextTimeRecord, nextTimeRTC, nextTimeSwitch, nextTimeLCD, time;
#define _maxADC 3
int vADC[_maxADC];
int tCode;
//-------------------------------------------------------------------

void setup() {
  analogReference(INTERNAL);
  // set up the LCD's number of rows and columns: 
  lcd.begin(8, 2); // 8 columns, 2 rows
  lcd.noCursor(); // cursor off
  Wire.begin(); //RTC
  Serial.begin(115200);
  Serial.flush();
  if (!SDstart()){ // SD error. Stop.
    LCDerror(_SDcard);
    while(true); //infinite loop
  }// if SDstart  
  nextTimeRecord=0;
  nextTimeRTC=0; 
  nextTimeSwitch=0;
  nextTimeLCD=0;
  LCDpage=0;
  firstString=true; 
  tCode=0;
}//setup  
//------------------ -------------------------------------------------

void loop() {
  time=millis();
  //-------------------------- Switch processing -------------------- 
  if (time>=nextTimeSwitch) {
    Mode=digitalRead(_Switch);
    if (Mode!=oldMode){
      oldMode=Mode; firstString=true;
    }//if  
    switch (Mode){
      //------------------------------- Adjust -----------------
      case _Adjust: 
        if (firstString){
          if (curPos>0){ //close SD-file if it opened
            Serial.println("SD close");
            if (!closeSD()) LCDerror(SDerror);
          }//   
          LCD_mode();
          Serial.println("set [Date][Time]");
          Serial.println("[y00][M00][d00][w00][h00][m00][s00]");
          firstString=false;
        }//if firstString  
        //------------ Adjust RTC -----------------
        if (Serial.available()>2)readSerialSetRTC();
        break;
      //----------------------------- Record --------------------
      case _Record: 
        if (firstString){
          LCD_mode();
          Serial.println("Record");
          firstString=false;
        }//if firstString  
        break;
    }//switch  
    nextTimeSwitch=nextTimeSwitch+_timeSwitchInterval;
  }//if nextTimeSwich
  
  //-------------------------- RTC processing ---------------------- 
  if (time>=nextTimeRTC) {
    readRTC(); 
    if (Mode==_Adjust) serialDate();
    nextTimeRTC=nextTimeRTC+_timeRTCinterval;
  }//if nextTimeRTC  

  //-------------------------- LCD processing ---------------------- 
  if (time>=nextTimeLCD) {
    switch (LCDpage){
      case 0: LCD_ADC(0); break;   
      case 1: LCD_ADC(1); break;   
      case 2: LCD_ADC(2); break;
      case 3: if (Mode==_Record) LCD_SD(); else LCD_mode(); 
              break;     
      default: LCDdate(); //final page more delay
    }//switch  
    LCDpage=LCDpage+1; if (LCDpage>_maxLCDpage) LCDpage=0;
    nextTimeLCD=nextTimeLCD+_timeLCDinterval;
  }//if nextTimeLCD  

  //-------------------------- Record processing ------------------- 
  if (time>=nextTimeRecord) {
    if (Mode==_Record){
      Serial.print("*"); // Data marker
      //Serial.print(BCDbyte(month),DEC); Serial.print(".");
      //Serial.print(BCDbyte(day),DEC); Serial.print(" ");
      //Serial.print(BCDbyte(hour),DEC); Serial.print(":");
      //Serial.print(BCDbyte(minute),DEC); Serial.print("; ");
      if (!writeSDdate()) LCDerror(SDerror); //date 
    }//if Record  
    for (int chanel=0; chanel<_maxADC; chanel++){
      vADC[chanel]=analogRead(chanel);
      if (Mode==_Record){
        Serial.print(vADC[chanel]); Serial.print("; "); 
        if (!writeSDint(vADC[chanel])) LCDerror(SDerror);
      }//if Mode Record 
    }//for chanel  
    nextTimeRecord=nextTimeRecord+_timeRecordInterval;
  }//if nextTimeRecord  
 
  //--------------------- overflow protection -----------------
  time=millis();
  if (time>nextTimeSwitch) 
    nextTimeSwitch=nextTimeSwitch+_timeSwitchInterval;
  if (time>nextTimeRTC) 
    nextTimeRTC=nextTimeRTC+_timeRTCinterval;
  if (time>nextTimeRTC) 
    nextTimeLCD=nextTimeLCD+_timeLCDinterval;
  if (time>nextTimeRecord) 
    nextTimeRecord=nextTimeRecord+_timeRecordInterval;
 }//loop 
 //-------------------------------------------------------------------
 
//-------------------- RTC adjust ---------------------  
 void readSerialSetRTC(){
    char c;
    c=Serial.read();
    switch (c){
      case 'y': year=serialBCD(); break;
      case 'M': month=serialBCD(); break;
      case 'd': day=serialBCD(); break;
      case 'w': weekD=serialBCD(); break;     
      case 'h': hour=serialBCD(); break;     
      case 'm': minute=serialBCD(); break;     
      case 's': second=serialBCD(); break;     
      default: 
        Serial.println(c+" Error");
        return;     
    }//switch 
    setRTC();
}//readSerialSetRTC

//-------------- SD-card --------------------------------------------
boolean SDstart(){
  // initialize SD card
  Serial.println("SD init start");  
  if (!SD.init()){ // Error // do not work SD.init=1 independent on SD
    Serial.println("SD Error");
    return false;
  }// if SD.init
  // initialize File Record
  if (!recordInit()){ // Error
    Serial.println("SD File Error");
    return false;
  }//if recordInit 
  Serial.println("File found");
  Serial.print("Size512="); Serial.println(fileSize);
  Serial.print("CurrentRecord="); Serial.println(curRecord);  
  Serial.print("Left512="); Serial.println(fileEnd-curBlock+1);  
  return true;
}//SDstart   

boolean closeSD(){
  if (curPos==0) return true;
  for (int i=curPos; i<_blockSize; i++) Buffer[i]=0xFF;
  if (!SD.writeBlock(curBlock,Buffer)){ //write data block to SD-card    
    SDerror=_SDfile;
  return false;
  }//if SD.writeBlock
  curRecord++; //next Record
  curBlock++; // next block
  curPos=0; //new begin
  return true;
}//closeSD  

boolean writeSDbyte(unsigned char code){
  if (curPos==0){ // write Current Record#
    Buffer[curPos]=lowByte(curRecord); curPos++;
    Buffer[curPos]=highByte(curRecord); curPos++;   
  }// if curPos
  Buffer[curPos]=code; curPos++;
  if (curPos>=_blockSize){ // write block
    if (!SD.writeBlock(curBlock,Buffer)){ //write data block to SD-card
      SDerror=_SDfile;
      return false;
    }// if SD.write  
    curBlock++; // next block
    curPos=0; // reset buffer
    if (curBlock>fileEnd){ // Stop conditions
      SDerror=_SDmemory;
      return false;
    }//if Stop conditions  
  }//if write block
  return true;
}//writeSDbyte 

boolean writeSDint(int code){
  if (!writeSDbyte(lowByte(code))) return false;
  if (!writeSDbyte(highByte(code))) return false;
  return true;
}//writeSDint  

boolean writeSDdate(){
  unsigned char b;
  b=BCDbyte(month); if (!writeSDbyte(b)) return false;
  b=BCDbyte(day); if (!writeSDbyte(b)) return false;
  b=BCDbyte(hour); if (!writeSDbyte(b)) return false;
  b=BCDbyte(minute); if (!writeSDbyte(b)) return false;
  return true;
}//writeSDdate  

// ----------------------  SD-file system ---------------------------
boolean markerSearch(){ // search for marker
  for (int i=0; i<_markLen; i++){
    if (Buffer[i]!=Marker[i]) return false;
  }//for i  
  return true;
}//markerSearch 
//--------------------------------------------------------------------

boolean recordInit(){ // initialize file system
  SDsize=SD.cardSize(); 
  
  // search for File marker
  boolean isMarking=false;
  for (long b=0; b<SDsize; b++){
    SD.readBlock(b,Buffer); 
    isMarking=markerSearch();
    if (isMarking) {
      fileStart=b;
      break;
    }//if    
  }//for b 
  if (!isMarking)  return false; // Error

  // Decode File Size
  for (int i=3; i>=0; i--){ 
    fileSize=fileSize<<8 | Buffer[_sizeOffset+i];
  }//for i  
  fileEnd=fileStart+fileSize;
  if (fileEnd>SDsize){
    fileEnd=SDsize;
  }//if size 
 
  //search for empty record
  unsigned int record;
  for (long b=fileStart+1; b<fileEnd; b++){
    SD.readBlock(b,Buffer);
    record=Buffer[0] | Buffer[1]<<8; // Record # 
    if (record==0xFFFF) {
      startBlock=b;
      break;
    }else curRecord=record;
  }//for b
  if (curRecord==0xFFFF) curRecord=0;
  else curRecord=curRecord+1;  

  if (startBlock==0) return false; // Error. No empty space
  curBlock=startBlock; 
 
  return true; //Ok
}//recordInit   

//----------------------- RTC ------------------------------
unsigned char BCDbyte(unsigned char b){
  return (b>>4)*10+(b&0x0F);  
}//BCDbyte

unsigned char serialBCD(){
  return (Serial.read()-'0')<<4 |(Serial.read()-'0');  
}//serialBCD

void setRTC(){
  Wire.beginTransmission(DS1307_ADDRESS);
  Wire.send(0); //set 0-page to start
  //BCD format
  Wire.send(second); // Set seconds & enable CLK
  Wire.send(minute);
  Wire.send(hour);
  Wire.send(weekD);
  Wire.send(day);
  Wire.send(month);
  Wire.send(year);
  Wire.send(0); // disable SQW out 
  Wire.endTransmission();
}//setRTC

//---------------------- RTC --------------------------------
void readRTC(){
  // Reset the register pointer
  Wire.beginTransmission(DS1307_ADDRESS);
  Wire.send(0); //set 0-page to start
  Wire.endTransmission();
  // Ask for 7 pages and stop
  Wire.requestFrom(DS1307_ADDRESS, 7); 
  //BCD format
  second=Wire.receive();
  minute=Wire.receive();
  hour=Wire.receive();
  weekD=Wire.receive(); 
  day=Wire.receive();
  month=Wire.receive();
  year=Wire.receive();  
}//readRTC  

//---------- Time output -----------------------------------------
void LCDhex(unsigned char b){
  if (b<0xf) lcd.print("0");
  lcd.print(b,HEX);
}//LCDhex 

void LCDdate(){
  lcd.clear(); 
  lcd.setCursor(0,0);
  LCDhex(day); lcd.print(".");
  LCDhex(month); lcd.print(".");
  LCDhex(year);  
  lcd.setCursor(0,1);  
  LCDhex(hour); lcd.print(":");
  LCDhex(minute); lcd.print(":"); 
  LCDhex(second); 
}//LCDdate 

void serialHex(unsigned char b){
  if (b<0xf) Serial.print("0");
  Serial.print(b,HEX);
}//serialHe 

void serialDate(){
  //print the date in BCD format
  serialHex(day); Serial.print(".");
  serialHex(month); Serial.print(".");
  serialHex(year); Serial.print(" ");
  serialHex(hour); Serial.print(":");
  serialHex(minute); Serial.print(":"); 
  serialHex(second); Serial.println();
}//printDate 

// ---------------- LCD error ----------------
void LCDerror(unsigned char error){
  lcd.clear();
  lcd.setCursor(0,0);
  lcd.print("-Error-");
  lcd.setCursor(0,1);
  switch (error) {  
    case _SDcard: lcd.print("SD-card"); break;
    case _SDfile: lcd.print("SD-file"); break;
    case _SDmemory: lcd.print("SDmemory"); break;
  }//switch  
}//LCDerror

// ---------------- LCD_ADC ----------------
void LCD_ADC(unsigned char chanel){
  lcd.clear();
  lcd.setCursor(0,0);
  lcd.print("ADC# "); lcd.print(chanel,DEC);
  lcd.setCursor(0,1);
  lcd.print(vADC[chanel],DEC);
}//LCD_ADC

// ---------------- LCD_SD ----------------
void LCD_SD(){
  lcd.clear();
  lcd.setCursor(0,0);
  lcd.print("Pos>"); lcd.print(curPos,DEC);
  lcd.setCursor(0,1);
  lcd.print("<");
  lcd.print(fileEnd-curBlock,DEC);
}//LCD_SD

// ---------------- LCD_mode ----------------
void LCD_mode(){
  lcd.clear();
  switch (Mode){
    case _Record: 
      lcd.setCursor(0,0); lcd.print("SD write");
      lcd.setCursor(5,1); lcd.print("Run");
      break;
    case _Adjust: 
      lcd.setCursor(0,0); lcd.print("PC>Setup");
      lcd.setCursor(1,1); lcd.print("SD stop");
      break;
  }//switch  
}//LCD_mode

