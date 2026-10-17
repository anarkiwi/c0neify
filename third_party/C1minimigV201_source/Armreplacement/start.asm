IDEbase			equ			$DA2000
IDEbase2		equ			$DA1000
; IDE register map
ide_data	            equ $00	; r/w
ide_error	            equ $04	; r
ide_features	equ $04	; w
ide_scount	            equ $08	; r/w
ide_lba0	            equ $0c	; r/w
ide_lba1	            equ $10	; r/w
ide_lba2	            equ $14	; r/w
ide_lba3	            equ $18	; r/w
ide_status	            equ $1c	; r
ide_command	equ $1c	; w

; IDE commands
idecmd_read_sector	equ $20
idecmd_write_sector	equ $30
idecmd_packet	equ $a0
idecmd_identify	equ $ec
idecmd_identifypacket	equ $a1

		xref	_main;
;		xref	_s;
		xref	_sprintf;
		xref	_DIRECT_TRANSFER_MODE
;       xdef      _SPI
       xdef      _putch
       xdef      _printf
       xdef      _SwapBBBB
       xdef      _SwapBB
       xdef      _SwapWW
       xdef      _GetSysCluster
       xdef      _MMC_Read
       xdef      _MMC_Write
       xref		_drive
       xref		_dirstart
RS232_base	            equ			$DA8000
		SECTION	,CODE
		move.l	#$1000,a7
		jmp _main
;_SPI:       
;;	   move.b    7(A7),$da8001
;	   move.b    7(A7),$da4001
;	   move.b	    $da4001,d0
;;	   move.w	    $da4000,d0
;;	   andi.l	#$ff,d0
;;@spi_1: move    $da4000,d0
;;	   bmi.s	@spi_1
;       rts
_putch:                           ; Basic character output routine
       move.b    7(A7),$da8001
       rts
       
_printf:                           ; Basic character output routine
		move.l	(a7)+,rettmp
		pea		rs_buf
		bsr		_sprintf
		move.l	(a7),a0
		move.l	rettmp,(a7)
_printfa
		move.b	(a0)+,d0
		beq		_printfe
       move.b    d0,$da8001
       bra		_printfa
_printfe       
       rts
rettmp	ds.l	1
rs_buf  ds.b	256

_SwapBBBB
		move.l	4(a7),d0
		rol.w		#8,d0
		swap	d0
		rol.w		#8,d0
		rts

_SwapBB
		move.l	4(a7),d0
		rol.w		#8,d0
		rts

_SwapWW
		move.l	4(a7),d0
		swap	d0
		rts


;unsigned long GetSysCluster(void)
_GetSysCluster
		move.w		$dee004,d0
		move.b		#$E0,d0		;Master
		btst		#9,d0
		beq.s		gsc0
		move.b		#$F0,d0		;Slave
gsc0	move.w		d0,_drive
		move.w		$dee000,d0
		swap		d0
		move.w		$dee002,d0
		move.l		d0,_dirstart
	    btst		#0,_drive
		beq.s		gsc2
   
		moveq		#-1,d0
		rts
		
gsc2	move.w  #$05E0,_drive    
		moveq		#0,d0
		move.l		d0,_dirstart
		rts

;unsigned long CF_Write(unsigned long lba, unsigned char *pReadBuffer)
;***************************************************
_MMC_Write
				movem.l		a0/a1,-(a7)
				move.l		16(a7),a0
				move.l		12(a7),d0
				lea			IDEbase,a1            		;LBA  Secundar
				btst		#2,_drive
				beq.s		write_b0
				lea			IDEbase2,a1            		;LBA  Primaer
write_b0		btst.b		#7,ide_status(a1)     		;busy?
				bne			write_b0
				move.b		#1,ide_scount(a1)     		;Sector Count = 1

write_b1		btst.b		#7,ide_status(a1)     		;busy?
				bne			write_b1
				move.b		d0,ide_lba0(a1)       		;7..0

				ror.l		#8,d0
write_b2		btst.b		#7,ide_status(a1)     		;busy?
				bne			write_b2
				move.b		d0,ide_lba1(a1)       		;15..8

				ror.l		#8,d0
write_b3		btst.b		#7,ide_status(a1)     		;busy?
				bne			write_b3
				move.b		d0,ide_lba2(a1)				;23..16

				ror.l		#8,d0
				and.w		#$0F,d0
				or.b		_drive+1,d0					;master/slave
;				or.b		#$E0,d0
write_b4		btst.b		#7,ide_status(a1)     		;busy?
				bne			write_b4
				move.b		d0,ide_lba3(a1)       		;27..24

write_block6
				btst.b		#7,ide_status(a1)     		;busy?
				bne			write_block6
				
				move		#$8000,d0
write_block5
				btst.b		#6,ide_status(a1)     		;ready?
				dbne		d0,write_block5
				beq.s		write_block_err
				move.b		#idecmd_write_sector,ide_command(a1)	;write Sector

;				move		#$8000,d0
;write_block8	btst.b		#7,ide_status(a1)
;				dbeq		d0,write_block8          		;wait for not busy
;				bne.s		write_block_errf

;write_block8	btst.b		#7,ide_status(a1)
;				bne.s		write_block8          			;wait for not busy

				move		#$8000,d0
write_block9	btst.b		#3,ide_status(a1)
				dbne		d0,write_block9          		;wait for DRQ
				beq.s		write_block_err

				move		#31,d0                			;write 256 Words
write_block7	move.l		(a0)+,(a1)
				move.l		(a0)+,(a1)
				move.l		(a0)+,(a1)
				move.l		(a0)+,(a1)
				dbf			d0,write_block7

;				suba.l		#$200,a0
;				move		#511,d0                			;write 256 Words
;write_block17	move.b		(a0)+,RS232_base
;				dbra		d0,write_block17

				movem.l		(a7)+,a0/a1
				moveq		#-1,d0						;OK
				rts
write_block_err	movem.l		(a7)+,a0/a1
				moveq		#0,d0						;Failure
				rts

;unsigned long CF_Read(unsigned long lba, unsigned char *pReadBuffer)
;***************************************************
_MMC_Read
;	    bsr			debug_hex
;				move		sr,-(a7)
;				or			#$700,sr					;disable irq
				movem.l		a0/a1,-(a7)
				move.l		16(a7),a0
				move.l		12(a7),d0
				lea			IDEbase,a1            		;LBA  Primaer
				btst		#2,_drive
				beq.s		read_b0
				lea			IDEbase2,a1            		;LBA  Secundar

read_b0			btst.b		#7,ide_status(a1)     		;busy?
				bne.s			read_b0
				move.b		#1,ide_scount(a1)     		;Sector Count = 1

read_b1			btst.b		#7,ide_status(a1)     		;busy?
				bne			read_b1
				move.b		d0,ide_lba0(a1)       		;7..0

				ror.l		#8,d0
read_b2			btst.b		#7,ide_status(a1)     		;busy?
				bne			read_b2
				move.b		d0,ide_lba1(a1)       		;15..8

				ror.l		#8,d0
read_b3			btst.b		#7,ide_status(a1)     		;busy?
				bne			read_b3
				move.b		d0,ide_lba2(a1)				;23..16

				ror.l		#8,d0
				and.w		#$0F,d0
				or.b		_drive+1,d0					;master/slave
;				or.b		#$E0,d0
read_b4			btst.b		#7,ide_status(a1)     		;busy?
				bne			read_b4
				move.b		d0,ide_lba3(a1)       		;27..24

read_block6
				btst.b		#7,ide_status(a1)     		;busy?
				bne			read_block6

				move		#$8000,d0
read_block5
				btst.b		#6,ide_status(a1)     		;ready?
				dbne		d0,read_block5
				beq.s		read_block_err

				move.b		#idecmd_read_sector,ide_command(a1)	;Read Sector
;				move		#$8000,d0
;read_block8		btst.b		#7,ide_status(a1)
;				dbeq		d0,read_block8          		;wait for not busy
;				bne.s		read_block_err

				move		#$8000,d0
read_block9		btst.b		#3,ide_status(a1)
				dbne		d0,read_block9          		;wait for DRQ
				beq.s		read_block_err

				move.b		_DIRECT_TRANSFER_MODE,d0
				bne.s		read_block20
				move.w		#31,d0                			;read 256 Words
read_block7		move.l		(a1),(a0)+
				move.l		(a1),(a0)+
				move.l		(a1),(a0)+
				move.l		(a1),(a0)+
				dbf			d0,read_block7

;				suba.l		#$200,a0
;				move		#511,d0                			;read 256 Words
;read_block17	move.b		(a0)+,RS232_base
;				dbf		d0,read_block17

				movem.l		(a7)+,a0/a1
				moveq		#-1,d0						;OK
;				and		#$F8FF,sr						;enable IRQ
				rts
read_block_err	;move.b		#'E',RS232_base			
				movem.l		(a7)+,a0/a1
;				move		 #$5555,_cachevalid			;invalid
				moveq		#0,d0						;Failure
;				and		#$F8FF,sr						;enable IRQ
				rts

read_block20	move.w		#31,d0                		;read 256 Words
				lea			$da4000,a0
				move.w 		#$40,4(a0)					;EnableDMode()
read_block21	move.l		(a1),(a0)
				move.l		(a1),(a0)
				move.l		(a1),(a0)
				move.l		(a1),(a0)
				dbf			d0,read_block21
				move.b		#$ff,(a0)

				move.w 		#$41,4(a0)					;DisableDMode()
				movem.l		(a7)+,a0/a1
				moveq		#-1,d0						;OK
;				and		#$F8FF,sr						;enable IRQ
				rts


		END
