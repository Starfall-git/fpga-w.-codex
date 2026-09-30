"""V0.14 / 68: persistent gallery, image-coordinate annotation and comparison."""
import math
from pathlib import Path
import tkinter as tk
from tkinter import ttk, filedialog, colorchooser, messagebox
from PIL import Image, ImageTk
from .snapshots import ImageDocument


def comparison_columns(sizes, width, height):
    """Choose the grid maximizing visible image area, including mixed aspect ratios."""
    if not sizes: return 1
    def score(cols):
        rows = math.ceil(len(sizes)/cols)
        w, h = max(1, width/cols-16), max(1, height/rows-48)
        return sum((min(w/iw,h/ih)**2)*iw*ih for iw,ih in sizes)
    return max(range(1,len(sizes)+1), key=score)


class Editor:
    """V0.18 / 85-87: object annotations; right-drag view; overwrite and restore."""
    TOOLS={'画笔批注':'pen','直线':'line','曲线（自由绘制）':'curve','矩形':'rectangle','圆形 / 椭圆':'ellipse',
           '三角形':'triangle','多边形':'polygon','菱形':'diamond','带箭头直线':'arrow','插入 / 修改文本':'text',
           '橡皮擦':'erase','擦除整个批注对象':'erase_object'}
    def __init__(self,parent,store,path,saved=None):
        self.store,self.path,self.saved=store,Path(path),saved
        self.doc=store.document(path)
        self.win=tk.Toplevel(parent);self.win.title('图片编辑 · '+self.path.stem);self.win.geometry('1150x800')
        self.tool=tk.StringVar(value='pen');self.tool_label=tk.StringVar(value='画笔批注');self.color='#ff4545'
        self.width=tk.IntVar(value=4);self.eraser_size=tk.IntVar(value=24);self.text_size=tk.IntVar(value=28)
        self.percent=tk.StringVar(value='100');self.scale=1.;self.pan_x=0.;self.pan_y=0.;self.origin=(0.,0.)
        self.pan_start=None;self.points=[];self.start=None;self.rectangle=None;self.polygon=[]
        bar=ttk.Frame(self.win,padding=8);bar.pack(fill='x')
        menu=ttk.Menubutton(bar,textvariable=self.tool_label);menu.pack(side='left')
        choices=tk.Menu(menu,tearoff=False)
        for name,tool in self.TOOLS.items():choices.add_command(label=name,command=lambda n=name,t=tool:self.set_tool(t,n))
        menu['menu']=choices
        ttk.Button(bar,text='鼠标框选裁剪',command=lambda:self.set_tool('crop','鼠标框选裁剪')).pack(side='left',padx=4)
        ttk.Button(bar,text='颜色',command=self.pick_color).pack(side='left')
        for label,var,limit in [('线宽',self.width,100),('橡皮大小',self.eraser_size,200),('字号',self.text_size,200)]:
            ttk.Label(bar,text=label).pack(side='left',padx=(8,2));ttk.Spinbox(bar,from_=1,to=limit,width=4,textvariable=var).pack(side='left')
        bar2=ttk.Frame(self.win,padding=8);bar2.pack(fill='x')
        for label,call in [('撤销',self.undo),('复原',self.restore),('上下翻转',lambda:self.flip(False)),('左右镜像',lambda:self.flip(True))]:
            ttk.Button(bar2,text=label,command=call).pack(side='left',padx=2)
        ttk.Label(bar2,text='尺寸 %').pack(side='left');entry=ttk.Entry(bar2,textvariable=self.percent,width=5);entry.pack(side='left');entry.bind('<Return>',lambda _:self.resize())
        for label,call in [('缩放',self.resize),('查看 −',lambda:self.zoom(.8)),('查看 +',lambda:self.zoom(1.25)),('自适应',self.fit)]:
            ttk.Button(bar2,text=label,command=call).pack(side='left',padx=2)
        bar3=ttk.Frame(self.win,padding=(8,0));bar3.pack(fill='x')
        for label,call in [('保存',self.save),('另存到仓库',self.save_copy),('下载图片',self.export)]:ttk.Button(bar3,text=label,command=call).pack(side='right',padx=4)
        self.info=tk.StringVar(value='右键按住拖动图像；多边形逐点点击、双击结束；点击已有文字可修改；橡皮不擦文字和原图。')
        ttk.Label(self.win,textvariable=self.info,wraplength=1080).pack(fill='x',padx=8,pady=5)
        self.canvas=tk.Canvas(self.win,bg='#17222d',highlightthickness=0);self.canvas.pack(fill='both',expand=True)
        for event,call in [('<ButtonPress-1>',self.press),('<B1-Motion>',self.drag),('<ButtonRelease-1>',self.release),
                           ('<Double-1>',self.double),('<ButtonPress-3>',self.pan_press),('<B3-Motion>',self.pan_drag)]:self.canvas.bind(event,call)
        self.canvas.bind('<ButtonRelease-3>',lambda _:setattr(self,'pan_start',None))
        self.canvas.bind('<Configure>',lambda _:self.render());self.win.bind('<Control-z>',lambda _:self.undo())
        self._fit_timer=self.win.after(80,self.fit)

    def set_tool(self,tool,label):
        self.tool.set(tool);self.tool_label.set(label);self.start=None;self.polygon=[];self.render()
    def render(self):
        image=self.doc.image;w,h=image.size;size=(max(1,round(w*self.scale)),max(1,round(h*self.scale)))
        self.photo=ImageTk.PhotoImage(image.resize(size,Image.Resampling.LANCZOS),master=self.win)
        self.origin=((self.canvas.winfo_width()-size[0])/2+self.pan_x,(self.canvas.winfo_height()-size[1])/2+self.pan_y)
        self.canvas.delete('all');self.canvas.create_image(*self.origin,image=self.photo,anchor='nw');self.rectangle=None
    def fit(self):
        self.pan_x=self.pan_y=0;w,h=self.doc.base.size
        self.scale=min(max(1,self.canvas.winfo_width())/w,max(1,self.canvas.winfo_height())/h,(8_000_000/(w*h))**.5);self.render()
    def fill(self):self.fit()  # compatibility for existing callers; no fill button
    def move(self,dx,dy):self.pan_x+=dx;self.pan_y+=dy;self.render()
    def pan_press(self,event):self.canvas.focus_set();self.pan_start=(event.x,event.y,self.pan_x,self.pan_y)
    def pan_drag(self,event):
        if self.pan_start:
            x,y,px,py=self.pan_start;self.pan_x=px+event.x-x;self.pan_y=py+event.y-y;self.render()
    def zoom(self,factor):
        w,h=self.doc.base.size;self.scale=max(.01,min(8,self.scale*factor,(8_000_000/(w*h))**.5));self.render()
    def point(self,event):
        margin=0 if self.tool.get()=='crop' else 1
        return (max(0,min(self.doc.base.width-margin,(event.x-self.origin[0])/self.scale)),max(0,min(self.doc.base.height-margin,(event.y-self.origin[1])/self.scale)))
    def screen(self,p):return self.origin[0]+p[0]*self.scale,self.origin[1]+p[1]*self.scale
    @staticmethod
    def number(var,default,limit):
        try:return max(1,min(limit,int(var.get())))
        except (ValueError,tk.TclError):return default
    def press(self,event):
        self.canvas.focus_set();p=self.point(event);tool=self.tool.get()
        text=self.doc.text_at(p)
        if tool=='text' or (text is not None and tool not in ('crop','erase','erase_object')):
            self.start=None;self.text_dialog(p,text);return
        if tool=='polygon':
            self.polygon.append(p)
            if len(self.polygon)>1:self.canvas.create_line(*self.screen(self.polygon[-2]),*self.screen(p),fill=self.color,width=2)
            return
        self.start=p;self.points=[p]
    def drag(self,event):
        if self.start is None:return
        p=self.point(event);tool=self.tool.get()
        if tool in ('pen','curve','erase','erase_object'):
            last=self.points[-1];self.points.append(p)
            width=self.number(self.eraser_size,24,200) if tool.startswith('erase') else self.number(self.width,4,100)
            self.canvas.create_line(*self.screen(last),*self.screen(p),fill='#b6c9d7' if tool.startswith('erase') else self.color,width=max(1,width*self.scale),capstyle='round')
        else:
            if self.rectangle:self.canvas.delete(self.rectangle)
            fn=self.canvas.create_line if tool in ('line','arrow') else self.canvas.create_oval if tool=='ellipse' else self.canvas.create_rectangle
            options={'fill':self.color} if tool in ('line','arrow') else {'outline':'#44dcff'}
            self.rectangle=fn(*self.screen(self.start),*self.screen(p),width=2,**options)
    def release(self,event):
        if self.start is None:return
        p=self.point(event);tool=self.tool.get()
        try:
            if tool=='crop':self.doc.crop((*self.start,*p));self.set_tool('pen','画笔批注');self.fit()
            elif tool in ('erase','erase_object'):self.doc.erase([*self.points,p],self.number(self.eraser_size,24,200),tool=='erase_object')
            else:self.doc.add(tool,[*self.points,p] if tool in ('pen','curve') else [self.start,p],self.color,self.number(self.width,4,100))
            self.render()
        except ValueError as e:self.info.set(str(e))
        self.start=None
    def double(self,event):
        if self.tool.get()=='polygon' and len(self.polygon)>=3:
            self.doc.add('polygon',self.polygon,self.color,self.number(self.width,4,100));self.polygon=[];self.render()
        return 'break'
    def text_dialog(self,point,index):
        win=tk.Toplevel(self.win);win.title('修改文本' if index is not None else '插入文本');win.transient(self.win)
        entry=tk.Text(win,width=40,height=5);entry.pack(padx=12,pady=12)
        if index is not None:entry.insert('1.0',self.doc.objects[index]['text'])
        def apply():
            text=entry.get('1.0','end-1c')
            if index is None:
                if text:self.doc.add('text',[point],self.color,self.number(self.text_size,28,200),text)
            else:self.doc.edit_text(index,text)
            win.destroy();self.render()
        ttk.Button(win,text='确定',command=apply).pack(pady=8);win.grab_set();entry.focus_set()
    def pick_color(self):
        color=colorchooser.askcolor(self.color,parent=self.win)[1]
        if color:self.color=color
    def undo(self):self.doc.undo();self.fit()
    def restore(self):self.doc.reset();self.fit();self.info.set('已清除全部图像修改和批注；点击保存后覆盖文件。')
    def flip(self,horizontal):self.doc.flip(horizontal);self.render()
    def resize(self):
        try:self.doc.resize(self.percent.get());self.fit()
        except ValueError as e:self.info.set(str(e))
    def save(self):
        try:
            self.store.replace_document(self.path,self.doc);self.info.set('已覆盖保存：'+self.path.name)
            if self.saved:self.saved()
        except OSError as e:messagebox.showerror('保存失败',str(e),parent=self.win)
    def save_copy(self):
        try:
            path=self.store.save(self.doc.image,parent=self.path.name);self.store.replace_document(path,self.doc)
            self.info.set('已另存：'+path.name)
            if self.saved:self.saved()
        except OSError as e:messagebox.showerror('保存失败',str(e),parent=self.win)
    def export(self):
        path=filedialog.asksaveasfilename(parent=self.win,initialfile=self.path.stem+'-edited.png',defaultextension='.png',filetypes=[('PNG','*.png'),('JPEG','*.jpg')])
        if path:
            try:self.doc.image.save(path)
            except OSError as e:messagebox.showerror('下载失败',str(e),parent=self.win)


class Comparison:
    def __init__(self,parent,store,paths,saved):
        self.store,self.paths,self.saved=store,paths,saved
        self.win=tk.Toplevel(parent);self.win.title(f'冻结帧对比 · {len(paths)} 张');self.win.geometry('1250x800')
        ttk.Label(self.win,text='双击图片即可编辑批注；保存后覆盖原文件，并刷新对比画面。',padding=8).pack(fill='x')
        self.area=ttk.Frame(self.win);self.area.pack(fill='both',expand=True)
        # Keep only bounded previews in the comparison; editor loads original.
        self.images=[]
        for p in paths:
            im=store.load(p);im.thumbnail((1280,720));self.images.append(im)
        self.timer=None;self.previous=(0,0);self.photos=[];self.cells=[]
        self.area.bind('<Configure>',self.configure)
        self.win.bind('<Destroy>',self.destroyed)

    def refresh(self):
        self.images=[]
        for p in self.paths:
            im=self.store.load(p);im.thumbnail((1280,720));self.images.append(im)
        self.render()
        if self.saved:self.saved()

    def destroyed(self,event):
        if event.widget==self.win and self.timer:
            self.win.after_cancel(self.timer);self.timer=None

    def configure(self,event):
        if (event.width,event.height)==self.previous:return
        self.previous=(event.width,event.height)
        if self.timer:self.win.after_cancel(self.timer)
        self.timer=self.win.after(100,self.render)

    def render(self):
        self.timer=None
        for c in self.cells:c.destroy()
        self.cells=[];self.photos=[]
        w,h=self.previous;cols=comparison_columns([im.size for im in self.images],w,h);rows=math.ceil(len(self.images)/cols)
        for index,(im,path) in enumerate(zip(self.images,self.paths)):
            cell=ttk.Frame(self.area,padding=4);cell.place(relx=(index%cols)/cols,rely=(index//cols)/rows,relwidth=1/cols,relheight=1/rows)
            preview=im.copy();preview.thumbnail((max(1,int(w/cols)-12),max(1,int(h/rows)-44)))
            photo=ImageTk.PhotoImage(preview,master=self.win);self.photos.append(photo)
            ttk.Label(cell,text=f'{index+1} · {path.stem[:22]}').pack()
            label=ttk.Label(cell,image=photo);label.pack(expand=True)
            label.bind('<Double-1>',lambda _,p=path:Editor(self.win,self.store,p,self.refresh));self.cells.append(cell)


class Gallery:
    def __init__(self,parent,store):
        self.store=store;self.win=tk.Toplevel(parent);self.win.title('冻结帧仓库');self.win.geometry('1050x750')
        bar=ttk.Frame(self.win,padding=10);bar.pack(fill='x')
        ttk.Button(bar,text='刷新',command=self.refresh).pack(side='left')
        ttk.Button(bar,text='对比所选',command=self.compare).pack(side='left',padx=8)
        ttk.Label(bar,text='勾选多张进行对比；点击缩略图打开编辑').pack(side='left')
        self.status=tk.StringVar();ttk.Label(self.win,textvariable=self.status,padding=8).pack(fill='x')
        self.canvas=tk.Canvas(self.win,highlightthickness=0)
        scroll=ttk.Scrollbar(self.win,command=self.canvas.yview);scroll.pack(side='right',fill='y')
        self.canvas.configure(yscrollcommand=scroll.set);self.canvas.pack(fill='both',expand=True)
        self.inner=ttk.Frame(self.canvas);self.canvas.create_window(0,0,window=self.inner,anchor='nw')
        self.inner.bind('<Configure>',lambda _:self.canvas.configure(scrollregion=self.canvas.bbox('all')))
        self.photos=[];self.selected={};self.refresh()

    def refresh(self):
        selected={p for p,v in self.selected.items() if v.get()}
        for c in self.inner.winfo_children():c.destroy()
        self.photos=[];self.selected={};entries=self.store.entries()
        self.status.set(f'{len(entries)} 张 · {self.store.root}')
        for index,path in enumerate(entries):
            try:im=self.store.load(path);im.thumbnail((230,135))
            except (OSError,ValueError):continue
            cell=ttk.Frame(self.inner,padding=8);cell.grid(row=index//4,column=index%4,sticky='nsew')
            photo=ImageTk.PhotoImage(im,master=self.win);self.photos.append(photo)
            ttk.Button(cell,image=photo,command=lambda p=path:Editor(self.win,self.store,p,self.refresh)).pack()
            v=tk.BooleanVar(value=path in selected);self.selected[path]=v
            ttk.Checkbutton(cell,text=path.stem[:22],variable=v).pack(anchor='w')

    def compare(self):
        paths=[p for p,v in self.selected.items() if v.get()]
        if len(paths)<2:messagebox.showinfo('选择图片','请至少选择两张冻结帧',parent=self.win);return
        Comparison(self.win,self.store,paths,self.refresh)
