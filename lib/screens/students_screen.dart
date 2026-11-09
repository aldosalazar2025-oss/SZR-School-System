import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';

import '../auth/auth_repository.dart';
import '../database/app_database.dart';
import '../carnet/carnet.dart';
import 'app_sidebar.dart';

class StudentsScreen extends StatefulWidget {
  const StudentsScreen({super.key,required this.user});
  final AuthUser user;
  @override
  State<StudentsScreen> createState()=>_StudentsScreenState();
}

class _StudentsScreenState extends State<StudentsScreen>{
  static Color get bg => P.bg;
  static Color get panel => P.panel;
  static Color get line => P.line;
  static Color get cyan => P.accent;
  static const red = Color(0xFFFF5275);
  final form=GlobalKey<FormState>();
  final names=TextEditingController(),surnames=TextEditingController(),dni=TextEditingController(),grade=TextEditingController(),section=TextEditingController(),search=TextEditingController();
  String shift='Mañana',filterGrade='Todos',filterSection='Todos',filterShift='Todos';
  Uint8List? photo;
  List<Map<String,Object?>> rows=[];
  bool busy=false;
  List<String> turnos=['Mañana','Tarde'];
  @override void initState(){super.initState();refresh();}
  @override void dispose(){names.dispose();surnames.dispose();dni.dispose();grade.dispose();section.dispose();search.dispose();super.dispose();}

  Future<void> refresh() async{
    final db=await AppDatabase.instance.database;
    final data=await db.query('alumnos',orderBy:'apellidos COLLATE NOCASE, nombres COLLATE NOCASE');
    final tn=await AppDatabase.instance.listaTurnos();
    if(!mounted)return;setState((){rows=data;turnos=tn;});
  }
  List<Map<String,Object?>> get filtered=>rows.where((r){
    final q=search.text.trim().toLowerCase();
    final full='${r['nombres']} ${r['apellidos']} ${r['dni']}'.toLowerCase();
    return (q.isEmpty||full.contains(q)) &&
      (filterGrade=='Todos'||r['grado']==filterGrade) &&
      (filterSection=='Todos'||r['seccion']==filterSection) &&
      (filterShift=='Todos'||r['turno']==filterShift);
  }).toList();
  List<String> options(String key)=>['Todos',...rows.map((r)=>(r[key]??'').toString()).where((s)=>s.isNotEmpty).toSet().toList()..sort()];

  Future<void> choosePhoto()async{
    final f=await FilePicker.platform.pickFiles(type:FileType.image,withData:true);
    if(f!=null&&f.files.single.bytes!=null)setState(()=>photo=f.files.single.bytes);
  }
  Future<void> saveStudent()async{
    if(!form.currentState!.validate())return;
    final db=await AppDatabase.instance.database;
    final cleanDni=dni.text.trim();
    if(cleanDni.isNotEmpty){
      final duplicate=await db.query('alumnos',where:'dni=?',whereArgs:[cleanDni],limit:1);
      if(duplicate.isNotEmpty){_message('Ya existe un estudiante con ese DNI.');return;}
    }
    final id=await db.insert('alumnos',{
      'nombres':names.text.trim(),'apellidos':surnames.text.trim(),'dni':cleanDni,
      'grado':grade.text.trim(),'seccion':section.text.trim(),'turno':shift,
      'foto':photo,'activo':1,'fecha_registro':DateTime.now().toIso8601String(),
    });
    final qr='ALUMNO:$id|DNI:$cleanDni';
    await db.update('alumnos',{'codigo_qr':qr},where:'id=?',whereArgs:[id]);
    names.clear();surnames.clear();dni.clear();grade.clear();section.clear();setState(()=>photo=null);
    await refresh();_message('Estudiante registrado y carnet generado.');
  }
  void _message(String s)=>ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(s)));

  Future<void> editStudent(Map<String,Object?> r)async{
    final n=TextEditingController(text:'${r['nombres']}'),a=TextEditingController(text:'${r['apellidos']}'),d=TextEditingController(text:'${r['dni']}'),g=TextEditingController(text:'${r['grado']}'),s=TextEditingController(text:'${r['seccion']}');
    String t='${r['turno']}';Uint8List? pic=r['foto'] as Uint8List?;
    await showDialog(context:context,builder:(ctx)=>StatefulBuilder(builder:(ctx,setD)=>AlertDialog(
      backgroundColor:panel,title:Text('Editar estudiante'),
      content:SizedBox(width:430,child:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
        _field(n,'Nombres'),_field(a,'Apellidos'),_field(d,'DNI'),Row(children:[Expanded(child:_field(g,'Grado')),SizedBox(width:8),Expanded(child:_field(s,'Sección'))]),
        DropdownButtonFormField<String>(value:t,items:(turnos.contains(t)?turnos:[...turnos,t]).map((v)=>DropdownMenuItem(value:v,child:Text(v))).toList(),onChanged:(v)=>setD(()=>t=v??t),decoration:InputDecoration(labelText:'Turno')),
        TextButton.icon(onPressed:()async{final f=await FilePicker.platform.pickFiles(type:FileType.image,withData:true);if(f!=null&&f.files.single.bytes!=null)setD(()=>pic=f.files.single.bytes);},icon:Icon(Icons.photo),label:Text('Cambiar fotografía')),
      ]))),
      actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:Text('Cancelar')),FilledButton(onPressed:()async{
        final db=await AppDatabase.instance.database;
        await db.update('alumnos',{'nombres':n.text.trim(),'apellidos':a.text.trim(),'dni':d.text.trim(),'grado':g.text.trim(),'seccion':s.text.trim(),'turno':t,'foto':pic},where:'id=?',whereArgs:[r['id']]);
        if(ctx.mounted)Navigator.pop(ctx);await refresh();
      },child:Text('Guardar cambios'))],
    )));
    n.dispose();a.dispose();d.dispose();g.dispose();s.dispose();
  }
  Future<void> toggleActive(Map<String,Object?> r)async{
    final active=(r['activo'] as int)==1?0:1;
    final db=await AppDatabase.instance.database;
    await db.update('alumnos',{'activo':active},where:'id=?',whereArgs:[r['id']]);await refresh();
  }
  Future<void> deleteOne(Map<String,Object?> r)async{
    final ok=await _confirm('Eliminar estudiante','Se eliminará el estudiante y no aparecerá en la lista. ¿Continuar?');
    if(!ok)return;
    final db=await AppDatabase.instance.database;
    await db.delete('alumnos',where:'id=?',whereArgs:[r['id']]);await refresh();
  }
  Future<bool> _confirm(String title,String body)async=>await showDialog<bool>(context:context,builder:(c)=>AlertDialog(title:Text(title),content:Text(body),actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:Text('Cancelar')),FilledButton(onPressed:()=>Navigator.pop(c,true),child:Text('Confirmar'))]))??false;
  Future<void> deleteAll()async{
    if(!await _confirm('Eliminar todos','Esta acción eliminará todos los estudiantes. ¿Deseas continuar?'))return;
    final db=await AppDatabase.instance.database;
    await db.delete('alumnos');await refresh();
  }
  Future<void> showQr(Map<String,Object?> r)async{
    final cfg=await CarnetConfig.load();
    // Se muestra el mismo PNG que se descarga: así la proporción 58:90 nunca se deforma.
    final png=await carnetRenderPng(cfg,CarnetData.fromRow(r),scale:1.0);
    if(!mounted)return;
    final sh=MediaQuery.of(context).size.height;
    final cw=math.min(320.0,math.max(160.0,(sh-260)*CarnetPainter.W/CarnetPainter.H));
    final ch=cw*CarnetPainter.H/CarnetPainter.W;
    await showDialog(context:context,builder:(c)=>AlertDialog(
      backgroundColor:panel,
      title:Text('Carnet · ${r['nombres']} ${r['apellidos']}'),
      content:SingleChildScrollView(child:Padding(padding:EdgeInsets.symmetric(vertical:8),child:Center(child:Image.memory(png,width:cw,height:ch,fit:BoxFit.contain,filterQuality:FilterQuality.medium,gaplessPlayback:true)))),
      actions:[
        TextButton.icon(onPressed:()=>downloadQr(r),icon:Icon(Icons.download),label:Text('Descargar')),
        TextButton(onPressed:()=>Navigator.pop(c),child:Text('Cerrar')),
      ]));
  }

  // ---------- Solo QR ----------
  String _qrData(Map<String,Object?> r){
    final q='${r['codigo_qr']??''}'.trim();
    return q.isNotEmpty?q:'ALUMNO:${r['id']}|DNI:${r['dni']??''}';
  }
  Future<void> showQrOnly(Map<String,Object?> r)async{
    final png=await qrRenderPng(_qrData(r),size:600);
    if(!mounted)return;
    final sh=MediaQuery.of(context).size.height;
    final side=math.min(280.0,(sh-260).clamp(140.0,280.0).toDouble());
    await showDialog(context:context,builder:(c)=>AlertDialog(
      backgroundColor:panel,
      title:Text('QR · ${r['nombres']} ${r['apellidos']}'),
      content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
        ClipRRect(borderRadius:BorderRadius.circular(12),child:Image.memory(png,width:side,height:side,filterQuality:FilterQuality.none)),
        SizedBox(height:10),
        Text('DNI: ${(r['dni']??'').toString().isEmpty?'—':r['dni']}',style:TextStyle(color:P.muted)),
      ])),
      actions:[
        TextButton.icon(onPressed:()=>downloadQrOnly(r),icon:Icon(Icons.download),label:Text('Descargar QR')),
        TextButton(onPressed:()=>Navigator.pop(c),child:Text('Cerrar')),
      ]));
  }
  Future<void> downloadQrOnly(Map<String,Object?> r)async{
    final png=await qrRenderPng(_qrData(r),size:1000);
    final name='QR_${(r['dni']??'').toString().isNotEmpty?r['dni']:r['id']}.png';
    if(await _saveFile('Guardar QR',name,'png',png))_message('QR descargado.');
  }
  Future<void> exportQrCodesPdf()async{
    final list=filtered.where((r)=>r['activo']==1).toList();
    if(list.isEmpty){_message('No hay estudiantes activos para exportar.');return;}
    _message('Generando ${list.length} códigos QR…');
    final doc=pw.Document();
    final imgs=<pw.MemoryImage>[];
    for(final r in list){imgs.add(pw.MemoryImage(await qrRenderPng(_qrData(r),size:600)));}
    const mm=PdfPageFormat.mm;
    const perPage=16; // 4 columnas x 4 filas en A4
    for(int start=0;start<list.length;start+=perPage){
      final end=math.min(start+perPage,list.length);
      final cells=<pw.Widget>[];
      for(int i=start;i<end;i++){
        final r=list[i];
        final dniTxt=(r['dni']??'').toString();
        cells.add(pw.Container(
          width:46*mm,
          padding:const pw.EdgeInsets.all(2*mm),
          decoration:pw.BoxDecoration(border:pw.Border.all(color:PdfColors.grey400,width:.5),borderRadius:pw.BorderRadius.circular(2*mm)),
          child:pw.Column(mainAxisSize:pw.MainAxisSize.min,children:[
            pw.Image(imgs[i],width:38*mm,height:38*mm),
            pw.SizedBox(height:1.5*mm),
            pw.Text('${r['apellidos']} ${r['nombres']}'.toUpperCase(),maxLines:2,textAlign:pw.TextAlign.center,style:pw.TextStyle(fontSize:7,fontWeight:pw.FontWeight.bold)),
            pw.Text(dniTxt.isEmpty?'—':'DNI: $dniTxt',style:const pw.TextStyle(fontSize:7)),
          ]),
        ));
      }
      doc.addPage(pw.Page(
        pageFormat:PdfPageFormat.a4,
        margin:const pw.EdgeInsets.all(8*mm),
        build:(ctx)=>pw.Wrap(spacing:3*mm,runSpacing:3*mm,alignment:pw.WrapAlignment.center,children:cells),
      ));
    }
    final bytes=await doc.save();
    if(await _saveFile('Descargar códigos QR PDF','codigos_qr_estudiantes.pdf','pdf',bytes))_message('PDF con ${list.length} códigos QR generado.');
  }

  Future<void> exportQrPdf()async{
    final list=filtered.where((r)=>r['activo']==1).toList();
    if(list.isEmpty){_message('No hay estudiantes activos para exportar.');return;}
    _message('Generando ${list.length} carnets…');
    final cfg=await CarnetConfig.load();
    final doc=pw.Document();
    final images=<pw.MemoryImage>[];
    for(final r in list){
      images.add(pw.MemoryImage(await carnetRenderPng(cfg,CarnetData.fromRow(r),scale:1.4)));
    }
    const mm=PdfPageFormat.mm;
    for(int start=0;start<images.length;start+=9){
      final chunk=images.skip(start).take(9).toList();
      doc.addPage(pw.Page(
        pageFormat:PdfPageFormat.a4,
        margin:const pw.EdgeInsets.all(8*mm),
        build:(ctx)=>pw.Center(child:pw.Wrap(spacing:3*mm,runSpacing:3*mm,alignment:pw.WrapAlignment.center,children:chunk.map((img)=>pw.Image(img,width:58*mm,height:90*mm)).toList())),
      ));
    }
    final bytes=await doc.save();
    if(await _saveFile('Descargar carnets PDF','carnets_estudiantes.pdf','pdf',bytes))_message('PDF de carnets generado (CR90, 9 por hoja A4).');
  }
  Future<void> downloadQr(Map<String,Object?> r)async{
    final cfg=await CarnetConfig.load();
    final png=await carnetRenderPng(cfg,CarnetData.fromRow(r));
    final name='Carnet_${r['dni']??r['id']}.png';
    if(await _saveFile('Guardar carnet',name,'png',png))_message('Carnet descargado.');
  }


  // ---------- Guardar archivos ----------
  Future<bool> _saveFile(String title,String fileName,String ext,List<int> bytes)async{
    try{
      var path=await FilePicker.platform.saveFile(dialogTitle:title,fileName:fileName,type:FileType.custom,allowedExtensions:[ext]);
      if(path==null)return false;
      if(!path.toLowerCase().endsWith('.$ext'))path='$path.$ext';
      await File(path).writeAsBytes(bytes,flush:true);
      return true;
    }catch(e){
      if(mounted)_message('No se pudo guardar el archivo: $e');
      return false;
    }
  }

  // ---------- Excel ----------
  String _cell(Data? d){
    final v=d?.value;
    if(v==null)return '';
    if(v is TextCellValue)return v.value.toString().trim();
    if(v is IntCellValue)return v.value.toString();
    if(v is DoubleCellValue){final n=v.value;return n==n.roundToDouble()?n.round().toString():n.toString();}
    return v.toString().trim();
  }
  String _norm(String s)=>s.toLowerCase().trim()
    .replaceAll('á','a').replaceAll('é','e').replaceAll('í','i').replaceAll('ó','o').replaceAll('ú','u').replaceAll('ñ','n');

  Future<void> exportExcel()async{
    final list=filtered;
    if(list.isEmpty){_message('No hay estudiantes para exportar.');return;}
    final x=Excel.createExcel();
    final name=x.getDefaultSheet()!;
    x.rename(name,'Estudiantes');
    final sh=x['Estudiantes'];
    sh.appendRow([for(final h in ['Apellidos','Nombres','DNI','Grado','Sección','Turno','Estado'])TextCellValue(h)]);
    for(final r in list){
      sh.appendRow([
        TextCellValue('${r['apellidos']??''}'),TextCellValue('${r['nombres']??''}'),TextCellValue('${r['dni']??''}'),
        TextCellValue('${r['grado']??''}'),TextCellValue('${r['seccion']??''}'),TextCellValue('${r['turno']??''}'),
        TextCellValue(r['activo']==1?'Activo':'Inactivo'),
      ]);
    }
    final bytes=x.encode();
    if(bytes==null){_message('No se pudo generar el Excel.');return;}
    if(await _saveFile('Exportar estudiantes','estudiantes.xlsx','xlsx',bytes))_message('Excel exportado (${list.length} estudiantes).');
  }

  Future<void> importExcel()async{
    if(busy)return;
    final f=await FilePicker.platform.pickFiles(type:FileType.custom,allowedExtensions:['xlsx'],withData:true);
    if(f==null)return;
    final bytes=f.files.single.bytes??(f.files.single.path==null?null:await File(f.files.single.path!).readAsBytes());
    if(bytes==null){_message('No se pudo leer el archivo.');return;}
    setState(()=>busy=true);
    try{
      final book=Excel.decodeBytes(bytes);
      if(book.tables.isEmpty){_message('El Excel no tiene hojas.');return;}
      final sheet=book.tables.values.first;
      final data=sheet.rows;
      if(data.length<2){_message('El Excel no tiene filas de datos.');return;}
      // Detecta columnas por el encabezado (primera fila)
      final idx=<String,int>{};
      for(var c=0;c<data.first.length;c++){
        final h=_norm(_cell(data.first[c]));
        if(h=='nombres'||h=='nombre')idx['nombres']=c;
        else if(h=='apellidos'||h=='apellido')idx['apellidos']=c;
        else if(h=='dni')idx['dni']=c;
        else if(h=='grado')idx['grado']=c;
        else if(h=='seccion')idx['seccion']=c;
        else if(h=='turno')idx['turno']=c;
      }
      if(!idx.containsKey('nombres')||!idx.containsKey('apellidos')){
        _message('La primera fila debe tener las columnas Nombres y Apellidos (opcional: DNI, Grado, Sección, Turno).');
        return;
      }
      String get(List<Data?> row,String k){final c=idx[k];return(c==null||c>=row.length)?'':_cell(row[c]);}
      final db=await AppDatabase.instance.database;
      var added=0,skipped=0;
      for(var i=1;i<data.length;i++){
        final row=data[i];
        final n=get(row,'nombres'),a=get(row,'apellidos'),d=get(row,'dni');
        if(n.isEmpty&&a.isEmpty)continue;
        if(n.isEmpty||a.isEmpty){skipped++;continue;}
        if(d.isNotEmpty){
          final dup=await db.query('alumnos',where:'dni=?',whereArgs:[d],limit:1);
          if(dup.isNotEmpty){skipped++;continue;}
        }
        var t=get(row,'turno');
        if(t.isEmpty)t='Mañana';
        else{
          final m=turnos.where((v)=>_norm(v)==_norm(t));
          t=m.isEmpty?t:m.first;
        }
        final id=await db.insert('alumnos',{
          'nombres':n,'apellidos':a,'dni':d,'grado':get(row,'grado'),'seccion':get(row,'seccion'),
          'turno':t,'activo':1,'fecha_registro':DateTime.now().toIso8601String(),
        });
        await db.update('alumnos',{'codigo_qr':'ALUMNO:$id|DNI:$d'},where:'id=?',whereArgs:[id]);
        added++;
      }
      await refresh();
      _message('Importación terminada: $added agregados, $skipped omitidos (duplicados o incompletos).');
    }catch(e){
      _message('Error al importar: $e');
    }finally{
      if(mounted)setState(()=>busy=false);
    }
  }

  @override Widget build(BuildContext context){
    final active=filtered.where((r)=>r['activo']==1).length;
    return Scaffold(backgroundColor:bg,body:Row(children:[
      AppSidebar(user:widget.user,selected:'Estudiantes'),
      Expanded(child:SafeArea(child:LayoutBuilder(builder:(ctx,box){
        final w=math.max(box.maxWidth,1100.0),h=math.max(box.maxHeight,560.0);
        return SingleChildScrollView(scrollDirection:Axis.horizontal,child:SizedBox(width:w,child:SingleChildScrollView(child:SizedBox(height:h,child:Column(children:[
      Container(height:66,padding:EdgeInsets.symmetric(horizontal:22),child:Row(children:[
        Icon(Icons.school,color:cyan,size:30),SizedBox(width:12),
        Text('Gestión de estudiantes',style:TextStyle(color:P.text,fontSize:22,fontWeight:FontWeight.bold)),
        Spacer(),
        TextButton.icon(onPressed:importExcel,icon:Icon(Icons.upload_file),label:Text('Importar Excel')),
        TextButton.icon(onPressed:exportExcel,icon:Icon(Icons.download),label:Text('Exportar')),
      ])),
      Expanded(child:Row(crossAxisAlignment:CrossAxisAlignment.start,children:[
        SizedBox(width:360,child:SingleChildScrollView(padding:EdgeInsets.fromLTRB(18,8,10,18),child:Container(padding:EdgeInsets.all(16),decoration:_panel(),child:Form(key:form,child:Column(children:[
          Text('Nuevo estudiante',style:TextStyle(color:P.text,fontSize:18,fontWeight:FontWeight.bold)),SizedBox(height:16),
          Row(children:[Expanded(child:_input(names,'Nombres')),SizedBox(width:8),Expanded(child:_input(surnames,'Apellidos'))]),
          _input(dni,'DNI',required:false),
          Row(children:[Expanded(child:_input(grade,'Grado')),SizedBox(width:8),Expanded(child:_input(section,'Sección'))]),
          DropdownButtonFormField<String>(value:shift,decoration:InputDecoration(labelText:'Turno'),items:turnos.map((v)=>DropdownMenuItem(value:v,child:Text(v))).toList(),onChanged:(v)=>setState(()=>shift=v??shift)),
          SizedBox(height:12),
          OutlinedButton.icon(onPressed:choosePhoto,icon:Icon(Icons.photo),label:Text(photo==null?'Fotografía (opcional)':'Fotografía seleccionada')),
          if(photo!=null)Padding(padding:EdgeInsets.all(8),child:Image.memory(photo!,height:70)),
          SizedBox(height:12),SizedBox(width:double.infinity,height:48,child:FilledButton.icon(onPressed:saveStudent,icon:Icon(Icons.qr_code),label:Text('Registrar y generar carnet'))),
        ]))))),
        Expanded(child:Container(margin:EdgeInsets.fromLTRB(8,8,18,18),padding:EdgeInsets.all(14),decoration:_panel(),child:Column(children:[
          TextField(controller:search,onChanged:(_)=>setState((){}),decoration:InputDecoration(prefixIcon:Icon(Icons.search),hintText:'Buscar por nombre o DNI...')),
          SizedBox(height:8),
          Row(children:[Expanded(child:_filterSelect('Grado',filterGrade,options('grado'),(v)=>setState(()=>filterGrade=v))),SizedBox(width:8),Expanded(child:_filterSelect('Sección',filterSection,options('seccion'),(v)=>setState(()=>filterSection=v))),SizedBox(width:8),Expanded(child:_filterSelect('Turno',filterShift,['Todos',...turnos],(v)=>setState(()=>filterShift=v)))]),
          SizedBox(height:12),
          Wrap(crossAxisAlignment:WrapCrossAlignment.center,spacing:8,runSpacing:4,children:[
            Text('$active estudiantes activos coinciden con el filtro',style:TextStyle(color:P.muted)),
            TextButton.icon(onPressed:exportQrPdf,icon:Icon(Icons.picture_as_pdf),label:Text('Descargar carnets PDF')),
            TextButton.icon(onPressed:exportQrCodesPdf,icon:Icon(Icons.qr_code_2),label:Text('Descargar QR PDF')),
            TextButton.icon(onPressed:deleteAll,icon:Icon(Icons.delete_forever,color:red),label:Text('Eliminar todos',style:TextStyle(color:red))),
          ]),
          Expanded(child:filtered.isEmpty?Center(child:Text('No hay estudiantes para mostrar.',style:TextStyle(color:P.text.withOpacity(.7)))):ListView.separated(itemCount:filtered.length,separatorBuilder:(_,__)=>Divider(color:line),itemBuilder:(ctx,i){
            final r=filtered[i];final isActive=r['activo']==1;final photoBytes=r['foto'] as Uint8List?;
            return ListTile(
              leading:photoBytes==null?CircleAvatar(child:Icon(Icons.person)):CircleAvatar(backgroundImage:MemoryImage(photoBytes)),
              title:Text('${r['nombres']} ${r['apellidos']}',style:TextStyle(color:P.text,fontWeight:FontWeight.bold)),
              subtitle:Text('DNI: ${r['dni']??'—'} · ${r['grado']??''} ${r['seccion']??''} · ${r['turno']}',style:TextStyle(color:P.muted2,fontSize:11)),
              trailing:Row(mainAxisSize:MainAxisSize.min,children:[
                _act('Ver carnet',Icons.badge,cyan,()=>showQr(r)),
                _act('Descargar carnet',Icons.download,cyan,()=>downloadQr(r)),
                _act('Ver QR',Icons.qr_code,cyan,()=>showQrOnly(r)),
                _act('Descargar solo QR',Icons.save_alt,cyan,()=>downloadQrOnly(r)),
                _act('Editar',Icons.edit,cyan,()=>editStudent(r)),
                _act(isActive?'Deshabilitar':'Habilitar',isActive?Icons.person_off:Icons.person,Colors.orange,()=>toggleActive(r)),
                _act('Eliminar',Icons.delete,red,()=>deleteOne(r)),
              ]),
            );
          })),
        ]))),
      ])),
    ]))))); }))),
    ]));
  }
  Widget _act(String tip,IconData icon,Color color,VoidCallback onTap)=>IconButton(tooltip:tip,onPressed:onTap,icon:Icon(icon,color:color,size:21),visualDensity:VisualDensity.compact,padding:EdgeInsets.zero,constraints:BoxConstraints(minWidth:36,minHeight:36));
  BoxDecoration _panel()=>BoxDecoration(color:panel,border:Border.all(color:line),borderRadius:BorderRadius.circular(14));
  Widget _input(TextEditingController c,String label,{bool required=true})=>Padding(padding:EdgeInsets.only(bottom:10),child:TextFormField(controller:c,style:TextStyle(color:P.text),decoration:InputDecoration(labelText:label,border:OutlineInputBorder()),validator:(v)=>required&&(v==null||v.trim().isEmpty)?'Completa $label':null));
  Widget _field(TextEditingController c,String label)=>Padding(padding:EdgeInsets.only(bottom:8),child:TextField(controller:c,decoration:InputDecoration(labelText:label)));
  Widget _filterSelect(String label,String value,List<String> values,ValueChanged<String> changed)=>DropdownButtonFormField<String>(value:values.contains(value)?value:'Todos',isExpanded:true,decoration:InputDecoration(labelText:label,contentPadding:EdgeInsets.symmetric(horizontal:10,vertical:8)),items:values.map((v)=>DropdownMenuItem(value:v,child:Text(v.isEmpty?'(Sin dato)':v,overflow:TextOverflow.ellipsis))).toList(),onChanged:(v){if(v!=null)changed(v);});
}
