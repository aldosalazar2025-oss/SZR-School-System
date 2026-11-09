import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../auth/auth_repository.dart';
import '../database/app_database.dart';
import 'app_sidebar.dart';
import '../theme/futuristic.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, required this.user});
  final AuthUser user;
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  static Color get bg => P.bg;
  static Color get panel => P.panel;
  static Color get line => P.line;
  static Color get cyan => P.accent;
  static Color get green => P.ok;
  static Color get red => P.err;
  static Color get orange => P.warn;
  static Color get blue => P.accent2;
  static Color get purple => P.accent;
  DateTime from=DateTime.now(), to=DateTime.now();
  String period='Hoy';
  bool loading=true;
  int students=0, early=0, punctual=0, late=0, absent=0, morning=0, afternoon=0;
  Map<String,int> shifts={};
  List<Color> get shiftColors=>[cyan,purple,orange,blue,green,red];
  List<_DayPoint> week=[];
  List<_StudentDay> dayStudents=[];

  int _countValue(List<Map<String, Object?>> rows) {
    if (rows.isEmpty) return 0;
    final value = rows.first.values.first;
    return value is int ? value : int.tryParse(value.toString()) ?? 0;
  }

  String date(DateTime d)=>'${d.year.toString().padLeft(4,'0')}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';
  String shortDate(DateTime d)=>'${d.day.toString().padLeft(2,'0')}/${d.month.toString().padLeft(2,'0')}';

  @override
  void initState(){super.initState();load();}

  Future<void> load() async {
    setState(()=>loading=true);
    try {
      await AppDatabase.instance.marcarInasistenciasPendientes();
      final db=await AppDatabase.instance.database;
      final total=_countValue(await db.rawQuery("SELECT COUNT(*) AS total FROM alumnos WHERE activo=1"));
      final rows=await db.rawQuery('''
        SELECT a.estado, al.turno, COUNT(*) AS n
        FROM asistencias a JOIN alumnos al ON al.id=a.alumno_id
        WHERE a.fecha>=? AND a.fecha<=? AND al.activo=1
        GROUP BY a.estado, al.turno
      ''',[date(from),date(to)]);
      int e=0,pu=0,l=0,f=0,m=0,t=0;
      final byShift=<String,int>{for(final n in await AppDatabase.instance.listaTurnos())n:0};
      for(final r in rows){
        final n=(r['n'] as int?)??0;
        final s=(r['estado'] as String? ?? '').toUpperCase();
        final turnoName=(r['turno'] as String? ?? '').trim();
        if(s=='TEMPRANO')e+=n;
        if(s=='PUNTUAL')pu+=n;
        if(s=='TARDE')l+=n;
        // por turno: solo estudiantes que sí asistieron (no las inasistencias)
        if(s=='TEMPRANO'||s=='PUNTUAL'||s=='TARDE'){byShift[turnoName]=(byShift[turnoName]??0)+n;}
      }

      m=byShift['Mañana']??0;
      t=byShift['Tarde']??0;
      // Ausentes = estudiantes activos × días lectivos del rango − asistencias registradas
      // (incluye a quienes no tienen ningún registro, no solo a los marcados FALTA).
      final today=DateTime.now();
      var end=DateTime(to.year,to.month,to.day);
      final todayD=DateTime(today.year,today.month,today.day);
      if(end.isAfter(todayD))end=todayD;
      var days=0;
      for(var d=DateTime(from.year,from.month,from.day);!d.isAfter(end);d=DateTime(d.year,d.month,d.day+1)){
        if(d.weekday<=5)days++;
      }
      f=(total*days-(e+pu+l)).clamp(0,1<<30).toInt();

      final selectedDay=date(to);
      final todayRows=await db.rawQuery('''
        SELECT al.id, al.nombres, al.apellidos, al.dni, al.grado, al.seccion, al.turno,
          (SELECT a.hora FROM asistencias a WHERE a.alumno_id=al.id AND a.fecha=?
           ORDER BY a.id ASC LIMIT 1) AS entrada,
          (SELECT a.estado FROM asistencias a WHERE a.alumno_id=al.id AND a.fecha=?
           ORDER BY a.id ASC LIMIT 1) AS estado,
          (SELECT COUNT(*) FROM asistencias a WHERE a.alumno_id=al.id AND a.fecha=?) AS registros
        FROM alumnos al WHERE al.activo=1 ORDER BY al.apellidos, al.nombres
      ''',[selectedDay,selectedDay,selectedDay]);

      final points=< _DayPoint>[];
      var cursor=DateTime(to.year,to.month,to.day);
      while(points.length<7){
        if(cursor.weekday<=5){
          final d=date(cursor);
          final count=_countValue(await db.rawQuery(
            "SELECT COUNT(DISTINCT a.alumno_id) AS total FROM asistencias a JOIN alumnos al ON al.id=a.alumno_id WHERE a.fecha=? AND al.activo=1 AND a.estado IN ('TEMPRANO','PUNTUAL','TARDE')",[d]));
          final rate=total==0?0.0:(count/total*100).clamp(0,100).toDouble();
          points.insert(0,_DayPoint(shortDate(cursor),count,rate));
        }
        cursor=cursor.subtract(Duration(days:1));
      }

      final records=todayRows.map((r){
        final status=(r['estado'] as String?)?.toUpperCase() ?? 'FALTA';
        return _StudentDay(
          name:'${r['nombres']??''} ${r['apellidos']??''}'.trim(),
          dni:(r['dni']??'').toString(),
          grade:'${r['grado']??''} ${r['seccion']??''}'.trim(),
          shift:(r['turno']??'').toString(),
          entry:(status=='FALTA'||r['entrada']==null)?'—':r['entrada'].toString().split(':').take(2).join(':'),
          status:status,
          count:(r['registros'] as int?)??0,
        );
      }).toList();

      if(!mounted)return;
      setState((){
        students=total;early=e;punctual=pu;late=l;absent=f;morning=m;afternoon=t;shifts=byShift;
        week=points;dayStudents=records;loading=false;
      });
    } catch(e){
      if(mounted)setState(()=>loading=false);
    }
  }

  void setPeriod(String p){
    final now=DateTime.now();
    setState((){
      period=p;
      if(p=='Hoy'){from=DateTime(now.year,now.month,now.day);to=from;}
      else if(p=='7 días lectivos'){to=DateTime(now.year,now.month,now.day);from=to.subtract(Duration(days:8));}
      else if(p=='Este mes'){from=DateTime(now.year,now.month,1);to=DateTime(now.year,now.month,now.day);}
    });
    load();
  }

  Future<void> pick(bool start) async{
    final selected=await showDatePicker(context:context,initialDate:start?from:to,firstDate:DateTime(2020),lastDate:DateTime(2100));
    if(selected==null)return;
    setState((){
      if(start){from=selected;if(to.isBefore(from))to=from;}
      else{to=selected;if(to.isBefore(from))from=to;}
      period='Personalizado';
    });
    load();
  }

  @override
  Widget build(BuildContext context){
    final present=early+punctual+late;
    final items=widget.user.isAdmin
      ? [_MenuItem(Icons.home_rounded,'Panel principal','Resumen general'),_MenuItem(Icons.school,'Estudiantes','Registrar y administrar'),_MenuItem(Icons.people,'Personal','Cuentas y permisos'),_MenuItem(Icons.qr_code_scanner,'Escanear QR','Entradas y salidas'),_MenuItem(Icons.edit_note,'Registro manual','Asistencia con observación'),_MenuItem(Icons.assessment,'Reportes','Consultar y exportar'),_MenuItem(Icons.schedule,'Horarios','Límites por turno')]
      : [_MenuItem(Icons.home_rounded,'Panel principal','Resumen general'),_MenuItem(Icons.qr_code_scanner,'Escanear QR','Entradas y salidas'),_MenuItem(Icons.edit_note,'Registro manual','Según permisos')];

    return Scaffold(
      backgroundColor:bg,
      body:Stack(children:[Row(children:[
        _sidebar(items),
        FContent(offset:0,child:Stack(children:[Positioned.fill(child:FuturisticBackground()),Column(children:[
          Container(height:66,padding:EdgeInsets.symmetric(horizontal:22),
            decoration:BoxDecoration(color:panel,border:Border(bottom:BorderSide(color:line)),boxShadow:P.shadow),
            child:Row(children:[
              PageIcon(Icons.insert_chart_outlined),
              SizedBox(width:12),
              Text('Panel principal',style:TextStyle(color:P.text,fontSize:21,fontWeight:FontWeight.bold)),
              Spacer(),
              Container(padding:EdgeInsets.symmetric(horizontal:12,vertical:6),decoration:BoxDecoration(color:cyan.withValues(alpha:.16),borderRadius:BorderRadius.circular(20),border:Border.all(color:cyan.withValues(alpha:.4))),child:Row(mainAxisSize:MainAxisSize.min,children:[Icon(Icons.person_rounded,size:15,color:P.text),SizedBox(width:6),Text(widget.user.username,style:TextStyle(color:P.text,fontSize:12,fontWeight:FontWeight.w600))])),
            ])),
          Expanded(child:SafeArea(child:RefreshIndicator(onRefresh:load,child:ListView(padding:EdgeInsets.fromLTRB(18,12,18,28),children:[
            Text('Sesión iniciada como ${widget.user.username} (${widget.user.isAdmin?'Administrador':'Personal de asistencia'})',style:TextStyle(color:P.muted,fontSize:13)),
            SizedBox(height:16),_filter(),
            if(loading)const Padding(padding:EdgeInsets.only(top:8),child:LinearProgressIndicator(minHeight:2)),
            SizedBox(height:14),
            LayoutBuilder(builder:(context,c){
              final cols=c.maxWidth>1200?8:c.maxWidth>650?4:2;
              final cards=[
                _metric(Icons.groups,'ESTUDIANTES','$students',cyan),
                _metric(Icons.verified_user,'PRESENTES','$present',green),
                _metric(Icons.person_off,'AUSENTES','$absent',red),
                _metric(Icons.wb_sunny,'TEMPRANO','$early',blue),
                _metric(Icons.check_circle,'PUNTUAL','$punctual',green),
                _metric(Icons.schedule,'TARDANZAS','$late',orange),
                _metric(Icons.wb_twilight,'MAÑANA','$morning',cyan),
                _metric(Icons.nights_stay,'TARDE','$afternoon',purple),
              ];
              return GridView.count(shrinkWrap:true,physics:NeverScrollableScrollPhysics(),crossAxisCount:cols,crossAxisSpacing:10,mainAxisSpacing:10,childAspectRatio:cols>=7?1.0:1.4,children:[for(int i=0;i<cards.length;i++)FadeSlideIn(delay:Duration(milliseconds:70*i),child:HoverLift(child:cards[i]))]);
            }),
            SizedBox(height:16),
            LayoutBuilder(builder:(context,c){
              final charts=[
                _chart('PUNTUALIDAD DEL DÍA',[_Legend(blue,'Temprano $early'),_Legend(green,'Puntual $punctual'),_Legend(orange,'Tarde $late'),_Legend(red,'Falta $absent')],_BarChart([early,punctual,late,absent],['Temprano','Puntual','Tarde','Falta'],[blue,green,orange,red])),
                _chart('PRESENTES VS. AUSENTES',[_Legend(green,'Presentes $present'),_Legend(red,'Ausentes $absent')],_Donut(present,absent)),
                _chart('PRESENTES POR TURNO',[for(int i=0;i<shifts.length;i++)_Legend(shiftColors[i%shiftColors.length],'${shifts.keys.elementAt(i)} ${shifts.values.elementAt(i)}')],_BarChart(shifts.values.toList(),shifts.keys.toList(),[for(int i=0;i<shifts.length;i++)shiftColors[i%shiftColors.length]])),
              ];
              if(c.maxWidth>900)return Row(crossAxisAlignment:CrossAxisAlignment.start,children:[for(int i=0;i<3;i++)Expanded(child:Padding(padding:EdgeInsets.only(right:i==2?0:10),child:FadeSlideIn(delay:Duration(milliseconds:350+120*i),child:charts[i])))]);
              return Column(children:charts.map((w)=>Padding(padding:EdgeInsets.only(bottom:12),child:FadeSlideIn(child:w))).toList());
            }),
            SizedBox(height:14),
            LayoutBuilder(builder:(context,c){
              final a=_chart('ASISTENCIA POR DÍA (ÚLTIMOS 7 DÍAS LECTIVOS)',[_Legend(green,'Presentes')],_LineChart(week.map((p)=>p.count.toDouble()).toList(),week.map((p)=>p.label).toList(),green));
              final b=_chart('TENDENCIA DE ASISTENCIA (%)',[_Legend(cyan,'Porcentaje de asistencia')],_LineChart(week.map((p)=>p.percent).toList(),week.map((p)=>p.label).toList(),cyan,percent:true));
              if(c.maxWidth>850)return Row(crossAxisAlignment:CrossAxisAlignment.start,children:[Expanded(child:Padding(padding:EdgeInsets.only(right:10),child:a)),Expanded(child:b)]);
              return Column(children:[a,SizedBox(height:12),b]);
            }),
            SizedBox(height:16),
            FadeSlideIn(delay:Duration(milliseconds:800),child:_attendanceTable(dayStudents,to)),
            SizedBox(height:12),
            Text('Estadísticas calculadas con los registros almacenados en este equipo.',style:TextStyle(color:P.subtle,fontSize:11)),
          ])))),
        ])])),
      ]),Positioned.fill(child:WelcomeOverlay(name:widget.user.username))]),
    );
  }

  Widget _sidebar(List<_MenuItem> items)=>AppSidebar(user:widget.user,selected:'Panel principal',onReload:load);

  Widget _filter()=>Container(padding:EdgeInsets.all(13),decoration:P.card(r:13),
    child:Wrap(spacing:9,runSpacing:9,crossAxisAlignment:WrapCrossAlignment.center,children:[
      Text('FILTRAR GRÁFICOS',style:TextStyle(color:P.text,fontWeight:FontWeight.bold,fontSize:12)),
      SizedBox(width:155,child:DropdownButtonFormField<String>(value:period,dropdownColor:panel,style:TextStyle(color:P.text),decoration:_decoration('Período'),
        items:['Hoy','7 días lectivos','Este mes','Personalizado'].map((v)=>DropdownMenuItem(value:v,child:Text(v))).toList(),
        onChanged:(v){if(v=='Personalizado'){setState(()=>period=v!);}else if(v!=null)setPeriod(v);})),
      OutlinedButton.icon(onPressed:()=>pick(true),icon:Icon(Icons.calendar_today,size:14),label:Text(date(from)),style:_buttonStyle()),
      OutlinedButton.icon(onPressed:()=>pick(false),icon:Icon(Icons.event,size:14),label:Text(date(to)),style:_buttonStyle()),
      FilledButton.icon(onPressed:load,icon:Icon(Icons.filter_alt,size:15),label:Text('Aplicar')),
    ]));
  InputDecoration _decoration(String s)=>InputDecoration(labelText:s,labelStyle:TextStyle(color:P.muted),filled:true,fillColor:bg,contentPadding:EdgeInsets.symmetric(horizontal:10,vertical:8),border:OutlineInputBorder(borderRadius:BorderRadius.circular(8)));
  ButtonStyle _buttonStyle()=>OutlinedButton.styleFrom(foregroundColor:P.text,side:BorderSide(color:line));
  Widget _metric(IconData icon,String label,String value,Color color)=>Container(padding:EdgeInsets.all(8),decoration:P.card(r:14),
    child:Column(mainAxisAlignment:MainAxisAlignment.center,children:[
      Container(width:32,height:32,decoration:BoxDecoration(color:color.withValues(alpha:.2),shape:BoxShape.circle),child:Icon(icon,color:color,size:19)),
      SizedBox(height:5),
      TweenAnimationBuilder<double>(tween:Tween<double>(begin:0,end:double.tryParse(value)??0),duration:Duration(milliseconds:900),curve:Curves.easeOutCubic,builder:(context,v,_)=>Text('${v.round()}',style:TextStyle(fontFamily:'Consolas',color:P.text,fontWeight:FontWeight.w800,fontSize:24,shadows:[Shadow(color:color.withValues(alpha:.6),blurRadius:12)]))),
      Text(label,textAlign:TextAlign.center,style:TextStyle(color:P.muted2,fontSize:10,fontWeight:FontWeight.w600,letterSpacing:.4))]));
  Widget _chart(String title,List<_Legend> legends,Widget graph)=>Container(height:255,padding:EdgeInsets.all(13),decoration:P.card(r:13),
    child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(title,style:TextStyle(color:P.muted,fontWeight:FontWeight.bold,fontSize:11)),SizedBox(height:10),Expanded(child:graph),Wrap(alignment:WrapAlignment.center,spacing:10,runSpacing:5,children:legends.map((l)=>Row(mainAxisSize:MainAxisSize.min,children:[Container(width:9,height:9,decoration:BoxDecoration(color:l.color,borderRadius:BorderRadius.circular(3))),SizedBox(width:4),Text(l.text,style:TextStyle(color:P.muted2,fontSize:9))])).toList())]));
  Widget _attendanceTable(List<_StudentDay> rows,DateTime selected)=>Container(padding:EdgeInsets.all(14),decoration:P.card(r:13),
    child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Row(children:[Icon(Icons.table_chart,color:cyan),SizedBox(width:8),Text('Asistencia del día',style:TextStyle(color:P.text,fontSize:17,fontWeight:FontWeight.bold)),SizedBox(width:8),Text('${shortDate(selected)} · ${rows.length} estudiantes',style:TextStyle(color:P.muted2,fontSize:11))]),
      SizedBox(height:12),
      if(rows.isEmpty)Padding(padding:EdgeInsets.all(18),child:Text('No hay estudiantes registrados.',style:TextStyle(color:P.muted)))
      else LayoutBuilder(builder:(context,box)=>SingleChildScrollView(scrollDirection:Axis.horizontal,child:ConstrainedBox(constraints:BoxConstraints(minWidth:box.maxWidth),child:DataTable(headingRowColor:WidgetStateProperty.all(P.head),dataRowMinHeight:42,dataRowMaxHeight:52,columnSpacing:22,
        columns:const [DataColumn(label:Text('ESTUDIANTE')),DataColumn(label:Text('GRADO / SECCIÓN')),DataColumn(label:Text('TURNO')),DataColumn(label:Text('ENTRADA')),DataColumn(label:Text('ESTADO')),DataColumn(label:Text('REGISTROS'))],
        rows:rows.map((r)=>DataRow(cells:[
          DataCell(Column(mainAxisAlignment:MainAxisAlignment.center,crossAxisAlignment:CrossAxisAlignment.start,children:[Text(r.name,style:TextStyle(color:P.text,fontWeight:FontWeight.w600)),if(r.dni.isNotEmpty)Text(r.dni,style:TextStyle(color:P.muted2,fontSize:10))])),
          DataCell(Text(r.grade.isEmpty?'—':r.grade,style:TextStyle(color:P.text))),
          DataCell(Text(r.shift,style:TextStyle(color:P.text))),
          DataCell(Text(r.entry,style:TextStyle(color:P.text))),
          DataCell(_status(r.status)),
          DataCell(Text('${r.count}',style:TextStyle(color:P.text))),
        ])).toList())))),
    ]));
  Widget _status(String s){final color=s=='TEMPRANO'?blue:s=='PUNTUAL'?green:s=='TARDE'?orange:red;return Container(padding:EdgeInsets.symmetric(horizontal:9,vertical:5),decoration:BoxDecoration(color:color.withValues(alpha:.22),border:Border.all(color:color.withValues(alpha:.7)),borderRadius:BorderRadius.circular(20)),child:Text(s,style:TextStyle(color:P.text,fontSize:10,fontWeight:FontWeight.bold)));}
  Widget _module(_MenuItem item)=>InkWell(onTap:()=>showDialog(context:context,builder:(_)=>AlertDialog(title:Text(item.title),content:Text('Este módulo está contemplado en el menú. Su funcionalidad se implementará en la siguiente etapa.'),actions:[TextButton(onPressed:()=>Navigator.pop(context),child:Text('Cerrar'))])),
    child:Container(padding:EdgeInsets.all(14),decoration:P.card(r:12),child:Row(children:[Icon(item.icon,color:cyan,size:27),SizedBox(width:12),Expanded(child:Column(mainAxisAlignment:MainAxisAlignment.center,crossAxisAlignment:CrossAxisAlignment.start,children:[Text(item.title,style:TextStyle(color:P.text,fontWeight:FontWeight.bold)),Text(item.subtitle,maxLines:1,overflow:TextOverflow.ellipsis,style:TextStyle(color:P.muted2,fontSize:11))])),Icon(Icons.chevron_right,color:P.subtle)])));
}

class _MenuItem{const _MenuItem(this.icon,this.title,this.subtitle);final IconData icon;final String title,subtitle;}
class _Legend{const _Legend(this.color,this.text);final Color color;final String text;}
class _DayPoint{const _DayPoint(this.label,this.count,this.percent);final String label;final int count;final double percent;}
class _StudentDay{const _StudentDay({required this.name,required this.dni,required this.grade,required this.shift,required this.entry,required this.status,required this.count});final String name,dni,grade,shift,entry,status;final int count;}

class _BarChart extends StatelessWidget{
  const _BarChart(this.values,this.labels,this.colors);final List<int> values;final List<String> labels;final List<Color> colors;
  @override Widget build(BuildContext context)=>TweenAnimationBuilder<double>(tween:Tween<double>(begin:0,end:1),duration:Duration(milliseconds:1000),curve:Curves.easeOutCubic,builder:(context,t,_)=>CustomPaint(painter:_BarPainter(values,labels,colors,t),child:SizedBox.expand()));
}
class _BarPainter extends CustomPainter{
  _BarPainter(this.values,this.labels,this.colors,this.t);final List<int> values;final List<String> labels;final List<Color> colors;final double t;
  @override void paint(Canvas canvas,Size size){final maxV=values.fold<int>(1,(a,b)=>a>b?a:b).toDouble();final base=size.height-22;final grid=Paint()..color=P.line..strokeWidth=.7;
    for(int i=0;i<4;i++){final y=8+(base-8)*i/3;canvas.drawLine(Offset(4,y),Offset(size.width-4,y),grid);}
    final slot=(size.width-14)/values.length;for(int i=0;i<values.length;i++){final h=(base-16)*values[i]/maxV*t;final rect=Rect.fromLTWH(7+slot*i+slot*.23,base-h,slot*.54,h);canvas.drawRRect(RRect.fromRectAndRadius(rect,Radius.circular(3)),Paint()..color=colors[i]);
      final vt=TextPainter(text:TextSpan(text:'${values[i]}',style:TextStyle(color:P.text,fontSize:10,fontWeight:FontWeight.bold)),textDirection:TextDirection.ltr)..layout();vt.paint(canvas,Offset(7+slot*i+(slot-vt.width)/2,base-h-14));
      final tp=TextPainter(text:TextSpan(text:labels[i],style:TextStyle(color:P.muted2,fontSize:9)),textDirection:TextDirection.ltr)..layout(maxWidth:slot);tp.paint(canvas,Offset(7+slot*i+(slot-tp.width)/2,base+5));}}
  @override bool shouldRepaint(covariant _BarPainter old)=>true;
}
class _LineChart extends StatelessWidget{
  const _LineChart(this.values,this.labels,this.color,{this.percent=false});final List<double> values;final List<String> labels;final Color color;final bool percent;
  @override Widget build(BuildContext context)=>TweenAnimationBuilder<double>(tween:Tween<double>(begin:0,end:1),duration:Duration(milliseconds:1200),curve:Curves.easeInOut,builder:(context,t,_)=>CustomPaint(painter:_LinePainter(values,labels,color,percent,t),child:SizedBox.expand()));
}
class _LinePainter extends CustomPainter{
  _LinePainter(this.values,this.labels,this.color,this.percent,this.t);final List<double> values;final List<String> labels;final Color color;final bool percent;final double t;
  @override void paint(Canvas canvas,Size size){if(values.isEmpty)return;canvas.save();canvas.clipRect(Rect.fromLTWH(0,0,size.width*t,size.height));final left=percent?30.0:8.0;final right=size.width-8;final top=8.0;final bottom=size.height-24;final maxV=percent?100.0:(values.fold<double>(1,(a,b)=>a>b?a:b));
    final grid=Paint()..color=P.line..strokeWidth=.7;for(int i=0;i<=4;i++){final y=top+(bottom-top)*i/4;canvas.drawLine(Offset(left,y),Offset(right,y),grid);
      if(percent){final tp=TextPainter(text:TextSpan(text:'${100-i*25}%',style:TextStyle(color:P.muted2,fontSize:8)),textDirection:TextDirection.ltr)..layout();tp.paint(canvas,Offset(0,y-5));}}
    final path=Path();for(int i=0;i<values.length;i++){final x=values.length==1?(left+right)/2:left+(right-left)*i/(values.length-1);final y=bottom-(values[i].clamp(0,maxV)/maxV)*(bottom-top);if(i==0)path.moveTo(x,y);else path.lineTo(x,y);
      final tp=TextPainter(text:TextSpan(text:labels[i],style:TextStyle(color:P.muted2,fontSize:8)),textDirection:TextDirection.ltr)..layout();tp.paint(canvas,Offset(x-tp.width/2,bottom+5));}
    canvas.drawPath(path,Paint()..color=color..style=PaintingStyle.stroke..strokeWidth=2.5..strokeCap=StrokeCap.round);
    for(int i=0;i<values.length;i++){final x=values.length==1?(left+right)/2:left+(right-left)*i/(values.length-1);final y=bottom-(values[i].clamp(0,maxV)/maxV)*(bottom-top);canvas.drawCircle(Offset(x,y),3,Paint()..color=color);}canvas.restore();
  }
  @override bool shouldRepaint(covariant _LinePainter old)=>true;
}
class _Donut extends StatelessWidget{const _Donut(this.present,this.absent);final int present,absent;@override Widget build(BuildContext context)=>TweenAnimationBuilder<double>(tween:Tween<double>(begin:0,end:1),duration:Duration(milliseconds:1100),curve:Curves.easeOutCubic,builder:(context,t,_)=>CustomPaint(painter:_DonutPainter(present,absent,t),child:SizedBox.expand()));}
class _DonutPainter extends CustomPainter{
  _DonutPainter(this.present,this.absent,this.t);final int present,absent;final double t;
  @override void paint(Canvas canvas,Size size){final center=Offset(size.width/2,size.height/2);final radius=size.shortestSide/2-12;final rect=Rect.fromCircle(center:center,radius:radius);final total=present+absent;final p=Paint()..style=PaintingStyle.stroke..strokeWidth=18;
    canvas.drawArc(rect,-1.5708,6.2832,false,p..color=P.line);if(total>0){canvas.drawArc(rect,-1.5708,6.2832*present/total*t,false,p..color=P.ok);canvas.drawArc(rect,-1.5708+6.2832*present/total*t,6.2832*absent/total*t,false,p..color=P.err);}
    final label=total==0?'0%':'${(present/total*100).round()}%';final tp=TextPainter(text:TextSpan(text:label,style:TextStyle(color:P.text,fontSize:19,fontWeight:FontWeight.bold)),textDirection:TextDirection.ltr)..layout();tp.paint(canvas,Offset(center.dx-tp.width/2,center.dy-tp.height/2));}
  @override bool shouldRepaint(covariant _DonutPainter old)=>old.present!=present||old.absent!=absent||old.t!=t;
}
