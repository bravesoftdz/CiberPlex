{Contiene las definiciones básicas que se necesitan para el objeto TCPCabina.
Contiene la definición de las siguientes clases:

* TSocketCabina-> Es un hilo, que se se usa para abrir una conexión Ethernet a la cabina.
                 A TSocketCabina no debe accederse directamente. Tiene su propia temporización
                 y rutinas de reconexión para mantener el enlace con la cabina remota.

* TCabConexion -> Es como una envoltura para el hilo TSocketCabina. Facilita el manejo de
                 la conexión por red, ya que administrar directamente al hilo, requiere
                 un cuidado mayor.
* TCabCuenta -> Contiene los parámetros de la cuenta de la cabina.

La conexión por red se implementa usando un hilo, porque la librería usada, solo
ofrece coenxiones con bloqueo, y lo que se desea es manejar la conexión por eventos.
Las únicas clases que debe usarse desde el exterior son "TCabConexion" y "TCabCuenta".

TSocketNilo-+
            |
            +- TNiloConexion (parámetros de la conexión)
            -- TCabCuenta    (parámetros de cuenta)

TNiloConexion se usa también, como un contenedor de las propiedades de la conexión serial,
así como "TCabCuenta", es un contenedor de los parámetros de cuenta.

La conexión por Red se implementa usando sockets con la librería "Synapse".

                                  Por Tito Hinostroza  27/09/2015
}
unit CibCabinaBase;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, LCLProc, MisUtils, blcksock, CibTramas;
type
  //Estado de conteo de las cabinas.
  TcabEstadoCuenta = (
    EST_NORMAL = 0,     //estado normal, sin contéo
    EST_CONTAN = 1,     //estado contando
    EST_PAUSAD = 2,     //estado pausado
    EST_MANTEN = 3      //estado en mantenimiento
  );

  { TCabCuenta }
  {Agrupa a las propiedades que definen el estado de cuenta de la cabina}
  TCabCuenta = class
  private
    function GetEstadoN: integer;
    procedure SetEstadoN(AValue: integer);
  public
    estado      : TcabEstadoCuenta;  //estado de la cabina
    hor_ini     : TDateTime;   //hora de inicio de alquiler
    tSolic      : TDateTime;   //tiempo solicitado
    tLibre      : boolean;     //Indica si tiene tiempo libre
    horGra      : boolean;     //Indica si tiene hora gratis
    //campos calculados
    property estadoN: integer read GetEstadoN write SetEstadoN;   //estado como entero
    function estadoStr: string;  //estado en texto
    function tSolicSeg: integer; //tiempo solicitado en segundos
    procedure Limpiar;
  public
    constructor Create;
  end;

type
  // Estados de la conexión de la cabina.
  TCabEstadoConex = (
    cecConectando,    //conectando
    cecConectado,     //conectado con socket
    cecDetenido,      //el proceso se detuvo (no hay control)
    cecMuerto         //proceso detenido
  );

  TEvCambiaEstado = procedure(nuevoEstado: TCabEstadoConex) of object;
  TEvTramaLista = procedure(NomCab: string; tram: TCPTrama) of object;

  { TSocketCabina }
  {Esta clase es la conexión a la cabina. Es un hilo para manejar las conexiones de
   manera asíncrona. Está pensada para ser usada solo por TCabConexion.
   El ciclo de conexión normal de TSocketCabina es:
   cecConectando -> cecConectado }
  TSocketCabina = class(TThread)
  private
    Festado: TCabEstadoConex;
    ip: string;
    sock: TTCPBlockSocket;
    regMsje: string;   //Usada como para pasar parámetro a EventoMensaje()
    ProcTrama: TCPProcTrama; //Para procesar tramas
    procedure AbrirConexion;
    procedure Abrir;
    procedure EventoTramaLista;
    procedure EventoCambiaEstado;
    procedure EventoRegMensaje;
    procedure ProcTramaRegMensaje(NomPC: string; msj: string);
  protected
    //Acciones sincronizadas
    procedure ProcesarTrama;
    procedure Setestado(AValue: TCabEstadoConex);
    procedure RegMensaje(msje: string);
    procedure Execute; override;
  public
    //Eventos. Se ejecutan de forma sincronizada.
    OnTramaLista  : TEvTramaLista;  //indica que hay una Trama lista esperando
    OnCambiaEstado: TEvCambiaEstado;
    OnRegMensaje  : TEvRegMensaje;
    property estado: TCabEstadoConex read Festado write Setestado;
    procedure TCP_envComando(comando: TCPTipCom; ParamX, ParamY: word; cad: string=
      '');
    constructor Create(ip0: string);
    Destructor Destroy; override;
  end;

  { TCabConexion }
  {Se usa esta clase como una envoltura para administrar la conexión TSocketCabina,
   ya que es un hilo, y el manejo directo se hace problemático, por las peculiaridades
   que tienen los hilos.
   El ciclo de conexión normal de TCabConexion es:
   cecMuerto -> cecConectando -> cecConectado -> cecMuerto
   Cuando se pierde la conexión puede ser:
   cecMuerto -> cecConectando -> cecConectado -> cecConectando -> cecConectado -> ...
   }
  TCabConexion = class
    procedure hiloCambiaEstado(nuevoEstado: TCabEstadoConex);
    procedure hiloRegMensaje(NomCab: string; msj: string);
    procedure hiloTerminate(Sender: TObject);
    procedure hiloTramaLista(NomCab: string; tram: TCPTrama);
  private
    FIP: string;
    Festado: TCabEstadoConex;
    hilo: TSocketCabina;
    function GetEstadoN: integer;
    procedure SetEstadoN(AValue: integer);
    procedure SetIP(AValue: string);
  public
    mac : string;   //Dirección Física
    property estado: TCabEstadoConex read Festado
             write Festado;   {"estado" es una propiedad de solo lectura, pero se habilita
                               la escritura, para cuando se usa CabConexión sin Red}
    property estadoN: integer read GetEstadoN write SetEstadoN;
    function estadoStr: string;
    property IP: string read FIP write SetIP;
  public
    OnCambiaEstado: TEvCambiaEstado;
    OnRegMensaje  : TEvRegMensaje;  //Indica que ha llegado un mensaje de la conexión
    OnTramaLista  : TEvTramaLista;  //indica que hay una trama lista esperando
    MsjError: string;       //Mensajes de error producidos.
    MsjesCnx: TstringList;  //Almanena los últimos mensajes de la conexión.
    procedure Conectar;
    procedure Desconectar;
    procedure TCP_envComando(comando: TCPTipCom; ParamX, ParamY: word; cad: string = '');
    constructor Create(ip0: string);
    destructor Destroy; override;
  end;


implementation
const
  MAX_LIN_MSJ_CNX = 10;  //Cantidad máxima de líneas que se guardarán de los msjes de conexión.
{ TCabCuenta }
function TCabCuenta.tSolicSeg: integer;
begin
  Result := round(tSolic*86400)
end;

procedure TCabCuenta.Limpiar;
begin
 estado := EST_NORMAL;

 horgra := False;
 tlibre := False;
end;

function TCabCuenta.GetEstadoN: integer;
begin
  Result := Ord(estado);
end;
procedure TCabCuenta.SetEstadoN(AValue: integer);
begin
  estado := TcabEstadoCuenta(AValue);
end;
function TCabCuenta.estadoStr: string;
begin
  case estado of
  EST_NORMAL: Result := 'Normal';
  EST_CONTAN: Result := 'Contando';
  EST_MANTEN: Result := 'En Mantenimiento';
  EST_PAUSAD: Result := 'Pausado';
  end;
end;
constructor TCabCuenta.Create;
begin
  estado := EST_NORMAL;
  {Inicia una fecha actual para que no cuente desde el año 1900, y desborde la variable
   entera de segundso transcurridos}
  hor_ini := date;
end;

{ TSocketCabina }
procedure TSocketCabina.Abrir;
{Intenta abrir una conexión}
begin
  estado := cecConectando;
  sock.Connect(ip, '80');  {Se bloquea unos segundo si no logra la conexión. No hay forma
                           directa de fijar un "Timeout", ya que depende de la implementación
                           del Sistema Operativo}
  if sock.LastError <> 0 then begin
    RegMensaje('Error de conexion.');
    { Genera temproización por si "sock.Connect", sale inmediátamente. Esto suele suceder
     cuando hay un error de red. }
    sleep(1000);
    exit;          //falló
  end;
  estado := cecConectado;
end;
procedure TSocketCabina.AbrirConexion;
begin
 RegMensaje('Abriendo puerto ...');
 repeat
   Abrir;  //puede tomar unos segundos
 until (estado = cecConectado) or Terminated;
end;
procedure TSocketCabina.EventoCambiaEstado;
// Dispara evento de cambio de estado
begin
  if OnCambiaEstado<>nil then begin
    OnCambiaEstado(Festado);
  end;
end;
procedure TSocketCabina.EventoRegMensaje;
begin
  if OnRegMensaje<>nil then begin
    OnRegMensaje('', regMsje);
  end;
end;
procedure TSocketCabina.ProcTramaRegMensaje(NomPC: string; msj: string);
{Este mensaje es geenrado por el procesador de tramas}
begin
 regMsje := msj;
 Synchronize(@EventoRegMensaje);
end;
procedure TSocketCabina.EventoTramaLista;
begin
  if OnTramaLista<>nil then begin
    OnTramaLista('', ProcTrama.trama);
  end;
end;
//Acciones sincronizadas
procedure TSocketCabina.ProcesarTrama;
{Procesa cuando se ha recibido una trama completa.}
begin
 Synchronize(@EventoTramaLista);
end;
procedure TSocketCabina.Setestado(AValue: TCabEstadoConex);
begin
 if Festado=AValue then Exit;
 Festado:=AValue;
 Synchronize(@EventoCambiaEstado); //dispara evento sicnronizando
end;
procedure TSocketCabina.RegMensaje(msje: string);
{Procedimiento para generar un mensaje dentro del hilo.}
begin
 regMsje := msje;
 Synchronize(@EventoRegMensaje);
end;
procedure TSocketCabina.Execute;
var
  buffer: String = '';
  tics: Integer;
  ticsSinRecibir: Integer;
begin
  AbrirConexion;
  if terminated then exit;  //por si se canceló
  //Aquí ya logró AbrirConexion el socket con el destino, debería haber control
  tics := 0;   //inicia cuenta
  ticsSinRecibir := 0;   //inicia cuenta
  RegMensaje('Enviando C_PRESENCIA.');
  sock.SendString(GenEncabez(0, C_PRESENCIA)); //tal vez debe verificarse primero si se puede enviar
  RegMensaje('Esperando respuesta ...');
  while not terminated do begin
    buffer := sock.RecvPacket(0);
    if buffer <> '' then begin
      // Hubo datos
      //n := length(buffer);
      //RegMensaje(IntToStr(n) +  ' bytes leídos.');
      tics := 0;
      ticsSinRecibir := 0;
      ProcTrama.DatosRecibidos(buffer, @ProcesarTrama);
    end;
    Inc(tics);
    Inc(ticsSinRecibir);
//    if tics mod 10 = 0 then RegMensaje('  tic=' + IntToStr(tics));
    if tics>60 then begin
      //No se ha enviado ningún comando en 6 segundos. Genera uno propio.
      RegMensaje('Enviando C_PRESENCIA.');
      sock.SendString(GenEncabez(0, C_PRESENCIA));
      tics := 0;
    end;
    if ticsSinRecibir>100 then begin
      //probablemente se cortó la conexión
      RegMensaje('Conexión perdida.');
      sock.CloseSocket;  //cierra conexión
      AbrirConexion;
      ticsSinRecibir := 0;
    end;
    sleep(100);  //periodo del lazo
  end;
end;
procedure TSocketCabina.TCP_envComando(comando: TCPTipCom; ParamX, ParamY: word;
  cad: string='');
{Envía una trama sencilla de datos, al socket. }
var
  s: string;
begin
  if estado <> cecConectado then
    exit;
  //Se debe enviar una trama
  writestr(s, comando);
  RegMensaje('  >>Enviado: ' + s + ' ');
  //ENvía
  if cad='' then begin
    //es una ProcTrama simple
    sock.SendString(GenEncabez(0, comando, ParamX, ParamY ));
  end else begin
    sock.SendString(GenEncabez(length(cad), comando, ParamX, ParamY ));
    sock.SendString(cad);
  end;
end;
constructor TSocketCabina.Create(ip0: string);
begin
  ip := ip0;
  Festado := cecConectando; {Estado inicial. Aún no está conectando, pero se asume que
                             está en proceso de conexión. Además, no existe estado
                             "cecDetenido" para TSocketCabina.
                             Notar que esta asignación de estado, no generará el evento de
                             cambio de estado, porque estamos en el constructor}
  sock := TTCPBlockSocket.Create;
  FreeOnTerminate := False;  //para controlar el fin
  ProcTrama:= TCPProcTrama.Create;
  ProcTrama.OnRegMensaje:=@ProcTramaRegMensaje;
  inherited Create(true);  //crea suspendido
end;
destructor TSocketCabina.Destroy;
begin
  ProcTrama.Destroy;
  sock.Destroy;
  RegMensaje('Proceso terminado.');
  //estado := cecMuerto;  //No es útil fijar el estado aquí, porque el objeto será destruido
  inherited Destroy;
end;

{ TCabConexion }
procedure TCabConexion.hiloCambiaEstado(nuevoEstado: TCabEstadoConex);
begin
  if Festado = nuevoEstado then exit;
  Festado := nuevoEstado;
  if OnCambiaEstado<>nil then OnCambiaEstado(Festado);
end;
procedure TCabConexion.hiloRegMensaje(NomCab: string; msj: string);
begin
  //debugln(nombre + ': '+ msj);
  MsjesCnx.Add(msj);  //Agrega mensaje
  //Mantiene tamaño, eliminando los más antiguos
  while MsjesCnx.Count>MAX_LIN_MSJ_CNX do begin
    MsjesCnx.Delete(0);
  end;
  if OnRegMensaje<>nil then OnRegMensaje('', msj);
end;
procedure TCabConexion.hiloTramaLista(NomCab: string; tram: TCPTrama);
begin
  //debugln(nombre + ': Trama recibida: '+ IntToStr(tram.tipTra));
  if OnTramaLista<>nil then OnTramaLista('', tram);
end;
procedure TCabConexion.hiloTerminate(Sender: TObject);
begin
  { Se ha salido del Execute() y el hilo ya no procesa la conexión. El hilo pasa a un
  estado suspendido, pero aún existe el objeto en memoria, porque no se le define con
  auto-destrucción.}
 hiloCambiaEstado(cecDetenido);
end;
function TCabConexion.estadoStr: string;
{Convierte TCabEstadoConex a cadena}
begin
 case Festado of
 cecConectando : exit('Conectando');
 cecConectado  : exit('Conectado');
 cecDetenido   : exit('Detenido');
 cecMuerto     : exit('Muerto');
 end;
end;
procedure TCabConexion.SetIP(AValue: string);
begin
  //solo se puede cambiar la IP cuando no hay conexión
  if estado in [cecMuerto, cecDetenido] then begin
    FIP:=AValue;
  end else begin
    self.MsjError := 'No se puede cambiar la IP de una cabina con conexión.';
  end;
end;
function TCabConexion.GetEstadoN: integer;
begin
  Result := ord(Festado);
end;
procedure TCabConexion.SetEstadoN(AValue: integer);
begin
 Festado := TCabEstadoConex(AValue);
end;
procedure TCabConexion.Conectar;
{Crea el hilo con la IP actual e inicia la conexión}
begin
  if Festado in [cecConectando, cecConectado] then begin
    // El hilo ya existe, y esta conectado o en proceso de conexión.
    { TODO : Para ser más precisos se debería ver si se le ha dado la orden de terminar
    el hilo mirando hilo.Terminated. De ser así, la muerte del hilo es solo cuestion
    de tiempo, (milisegundos si está en estado cecConectado o segundos si está en
    estado cecConectando)
    }
    exit;
  end;
  if estado = cecDetenido then begin
    // El proceso fue terminado, tal vez porque dio error.
    hilo.Destroy;   //libera referencia
    hilo := nil;
    //Festado := cecMuerto;  //No es muy útil, fijar este estado, porque seguidamente se cambiará
  end;
  hilo := TSocketCabina.Create(FIP);
  hilo.OnCambiaEstado:=@hiloCambiaEstado; //para detectar cambios de estado
  hilo.OnCambiaEstado(hilo.estado);       //genera el primer evento de estado
  hilo.OnTerminate:=@hiloTerminate;       //para detectar que ha muerto
  hilo.OnRegMensaje:=@hiloRegMensaje;     //Para recibir mensajes
  hilo.OnTramaLista:=@hiloTramaLista;
  // Inicia el hilo. Aquí empezará con el estado "Conectando"
  hilo.Start;
end;
procedure TCabConexion.Desconectar;
begin
  if Festado = cecMuerto then begin
    exit;  //Ya está muerto el proceso, o está a punto de morir
  end;
  // La única forma de matar al proceso es dándole la señal
  hilo.Terminate;
  {puede tomar unos segundos hasta que el hilo pase a estado suspendido (milisegundos si está
  en estado cecConectado o segundos si está en  estado cecConectando)
  }
end;
procedure TCabConexion.TCP_envComando(comando: TCPTipCom; ParamX, ParamY: word;
  cad: string = '');
begin
  if estado<>cecConectado then
    exit;
  hilo.TCP_envComando(comando, ParamX, ParamY, cad);
end;
constructor TCabConexion.Create(ip0: string);
begin
  MsjesCnx:= TstringList.Create;
  FIP := ip0;
  Festado := cecMuerto;  //este es el estado inicial, porque no se ha creado el hilo
  //Conectar;  //No inicia la conexión
end;
destructor TCabConexion.Destroy;
begin
  //Verifica si debe detener el hilo
  if Festado<>cecMuerto then begin
    if hilo = nil then begin
      {Este es un caso especial, cuando no se llegó a conectar nunca al hilo o cuando se
       usa a TCabConexion, sin red. Por los tanto no se crea nunca el hilo}
    end else begin
      //Caso normal en que se ha creado el hilo
      hilo.Terminate;
      hilo.WaitFor;  //Si no espera a que muera, puede dejarlo "zombie"
      hilo.Destroy;
      //estado := cecMuerto;  //No es útil fijar el estado aquí, porque el objeto será destruido
    end;
  end;
  MsjesCnx.Destroy;
  inherited Destroy;
end;

end.

